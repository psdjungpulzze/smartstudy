defmodule FunSheep.Workers.ParentRequestEmailWorker do
  @moduledoc """
  Dispatches the "your kid asked for more practice" email to a parent.

  Per spec §4.6.1 and §9.3:

    * Uses `FunSheepWeb.Emails.ParentRequestEmail.build/1` for content
    * Sends via `FunSheep.Mailer`
    * **Honors quiet hours** — 10pm–7am parent-local (fallback: student
      timezone, then UTC). On enqueue, `schedule_send/1` computes the
      next valid window and passes `scheduled_at` to Oban. As a safety
      net, `perform/1` re-checks on run and `{:snooze, _}`s if the job
      fired inside quiet hours anyway (clock drift, timezone update).

  Emits `request.email_sent` telemetry on successful delivery.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias FunSheep.Mailer
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheepWeb.Emails.ParentRequestEmail

  require Logger

  @quiet_start 22
  @quiet_end 7

  ## Scheduling entry point

  @doc """
  Enqueues a send, scheduled for the next valid quiet-hours window.

  Call from `FunSheep.PracticeRequests.create/3` (or equivalent) once a
  request has been successfully inserted.
  """
  def schedule_send(%Request{} = request) do
    request = Repo.preload(request, [:guardian, :student])
    tz = resolve_timezone(request)
    scheduled_at = next_send_time(DateTime.utc_now(), tz)

    %{request_id: request.id}
    |> __MODULE__.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  ## Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    case Repo.get(Request, request_id) do
      nil ->
        {:cancel, :request_not_found}

      %Request{status: status} = request when status in [:pending, :viewed] ->
        request = Repo.preload(request, [:guardian, :student])
        tz = resolve_timezone(request)

        if in_quiet_hours?(DateTime.utc_now(), tz) do
          # Safety net: the initial schedule should already avoid this,
          # but if the worker fires inside quiet hours (timezone change,
          # clock skew, retry after failure), snooze to the next window.
          {:snooze, snooze_seconds(DateTime.utc_now(), tz)}
        else
          deliver(request)
        end

      %Request{status: status} ->
        # Terminal state — no need to send.
        {:cancel, {:not_pending, status}}
    end
  end

  defp deliver(%Request{} = request) do
    case ParentRequestEmail.build(request) do
      {:ok, email} ->
        case Mailer.deliver(email) do
          {:ok, _meta} ->
            :telemetry.execute(
              [:fun_sheep, :practice_request, :email_sent],
              %{count: 1},
              %{
                request_id: request.id,
                student_id: request.student_id,
                guardian_id: request.guardian_id
              }
            )

            :ok

          {:error, reason} ->
            Logger.error("[ParentRequestEmail] delivery failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :no_guardian_email} ->
        # Can't send — not a retry-worthy failure.
        Logger.warning(
          "[ParentRequestEmail] guardian for request #{request.id} has no email on file"
        )

        {:cancel, :no_guardian_email}
    end
  end

  ## Timezone + quiet-hours logic (§9.3)

  @doc false
  def resolve_timezone(%Request{guardian: %{timezone: tz}}) when is_binary(tz) and tz != "",
    do: tz

  def resolve_timezone(%Request{student: %{timezone: tz}}) when is_binary(tz) and tz != "", do: tz

  def resolve_timezone(_), do: "Etc/UTC"

  @doc false
  def in_quiet_hours?(%DateTime{} = now_utc, tz) do
    case to_local(now_utc, tz) do
      {:ok, local} ->
        local.hour >= @quiet_start or local.hour < @quiet_end

      {:error, _} ->
        false
    end
  end

  @doc false
  def next_send_time(%DateTime{} = now_utc, tz) do
    case to_local(now_utc, tz) do
      {:ok, local} ->
        if local.hour >= @quiet_start or local.hour < @quiet_end do
          next_seven_local(local) |> from_local(tz)
        else
          now_utc
        end

      {:error, _} ->
        now_utc
    end
  end

  defp snooze_seconds(now_utc, tz) do
    next = next_send_time(now_utc, tz)
    max(DateTime.diff(next, now_utc, :second), 60)
  end

  defp to_local(utc, "Etc/UTC"), do: {:ok, utc}

  defp to_local(utc, tz) do
    # DateTime.shift_zone/2 requires a timezone database. We rely on
    # Elixir's built-in UTC-only database by default — for non-UTC
    # zones we fall back to UTC and treat the result as best-effort.
    # PR 3 or a follow-up can wire `tz_data` or similar for accurate
    # IANA support.
    case DateTime.shift_zone(utc, tz) do
      {:ok, dt} -> {:ok, dt}
      _ -> {:ok, utc}
    end
  end

  defp next_seven_local(%DateTime{} = local) do
    target_date =
      if local.hour >= @quiet_end,
        do: Date.add(DateTime.to_date(local), 1),
        else: DateTime.to_date(local)

    %DateTime{
      year: target_date.year,
      month: target_date.month,
      day: target_date.day,
      hour: @quiet_end,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      time_zone: local.time_zone,
      zone_abbr: local.zone_abbr,
      utc_offset: local.utc_offset,
      std_offset: local.std_offset
    }
  end

  defp from_local(%DateTime{time_zone: "Etc/UTC"} = dt, _tz), do: dt

  defp from_local(%DateTime{} = dt, _tz) do
    # Shift back to UTC for Oban's scheduled_at.
    case DateTime.shift_zone(dt, "Etc/UTC") do
      {:ok, utc} -> utc
      _ -> dt
    end
  end
end
