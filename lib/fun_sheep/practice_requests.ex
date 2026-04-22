defmodule FunSheep.PracticeRequests do
  @moduledoc """
  Flow A — student-initiated practice requests.

  See `~/s/funsheep-subscription-flows.md` §4 and §7.5.

  A student who has hit (or nearly hit) their weekly free-tier cap can
  send a request to a linked guardian (usually a parent) to unlock
  unlimited practice. The guardian accepts → Interactor Billing checkout
  → webhook activates the subscription with
  `paid_by_user_role_id = guardian` and `origin_practice_request_id = request`.

  **Ethical guardrails (§2.3).** Conversions must fire on real, voluntary,
  positive student behaviour. This module enforces:
    * one pending request per student (partial unique index)
    * 48-hour cooldown after a decline
    * maximum one reminder per request
    * 7-day auto-expiry (see `FunSheep.Workers.RequestExpiryWorker`)

  **No fake content (CLAUDE.md).** Every activity number in `metadata`
  comes from `FunSheep.Engagement.StudySessions.parent_activity_summary/2`
  and `FunSheep.Assessments.list_upcoming_schedules/2`. We never fabricate
  streaks, test dates, or other metrics.
  """

  import Ecto.Query

  alias FunSheep.Accounts.UserRole
  alias FunSheep.Assessments
  alias FunSheep.Engagement.StudySessions
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheep.Workers.ParentRequestEmailWorker

  # §4.7 — cooldown after decline before student can re-ask.
  @decline_cooldown_hours 48

  ## Public API

  @doc """
  Creates a new pending request from a student to a guardian (optional).

  Enforces: one pending request per student; 48-hour cooldown after decline;
  populates `metadata` from real activity. Emits `request.created` telemetry.

  Accepted `attrs`:
    * `:reason_code` — required, one of `#{inspect(Request.reason_codes())}`
    * `:reason_text` — required when `:reason_code == :other`, max 140 chars
  """
  def create(student_id, guardian_id, attrs) when is_binary(student_id) do
    with :ok <- ensure_no_recent_decline(student_id) do
      metadata = build_snapshot(student_id)

      changeset =
        Request.create_changeset(%Request{}, %{
          student_id: student_id,
          guardian_id: guardian_id,
          reason_code: attrs[:reason_code] || attrs["reason_code"],
          reason_text: attrs[:reason_text] || attrs["reason_text"],
          metadata: metadata
        })

      handle_insert(Repo.insert(changeset))
    end
  end

  defp handle_insert({:ok, request}) do
    emit(:created, request)
    schedule_parent_email(request)
    {:ok, request}
  end

  defp handle_insert({:error, %Ecto.Changeset{errors: errors} = cs}) do
    if Keyword.has_key?(errors, :student_id) do
      {:error, :already_pending}
    else
      {:error, cs}
    end
  end

  defp schedule_parent_email(%Request{guardian_id: nil}), do: :ok

  defp schedule_parent_email(%Request{} = request) do
    # Best-effort — a failure to schedule the email should not roll back
    # the request creation itself. The parent can still act via the
    # in-app card (§4.6.2) if the email path fails.
    case ParentRequestEmailWorker.schedule_send(request) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("[PracticeRequests] failed to schedule parent email: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Marks a request as viewed (transitions `:pending` → `:viewed`).

  Idempotent — calling on a `:viewed` or terminal request is a no-op and
  returns the existing record. Emits `request.viewed` telemetry only on
  the first transition.
  """
  def view(request_id) do
    case Repo.get(Request, request_id) do
      nil ->
        {:error, :not_found}

      %Request{status: :pending} = request ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok, updated} =
          request
          |> Request.transition_changeset(%{status: :viewed, viewed_at: now})
          |> Repo.update()

        emit(:viewed, updated)
        {:ok, updated}

      %Request{} = request ->
        {:ok, request}
    end
  end

  @doc """
  Accepts a request — race-safe via `SELECT ... FOR UPDATE` (§9.2).

  Stamps `decided_at`, transitions `:pending | :viewed` → `:accepted`.
  Pass `subscription_id` in `attrs` to link the paid subscription back
  to the request. Emits `request.accepted` telemetry.

  Concurrent accepts (two parents tapping at once) will see the losing
  caller get `{:error, :not_pending}` once the first commits, thanks to
  the row lock plus partial unique index on pending requests.
  """
  def accept(request_id, attrs \\ %{}) when is_binary(request_id) do
    case Repo.transaction(fn -> do_accept_txn(request_id) end) do
      {:ok, request} ->
        emit(:accepted, request, %{subscription_id: attrs[:subscription_id]})
        {:ok, request}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_accept_txn(request_id) do
    request =
      from(r in Request, where: r.id == ^request_id, lock: "FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(request) ->
        Repo.rollback(:not_found)

      not Request.pending?(request) ->
        Repo.rollback({:not_pending, request.status})

      true ->
        apply_accept_transition(request)
    end
  end

  defp apply_accept_transition(request) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    request
    |> Request.transition_changeset(%{status: :accepted, decided_at: now})
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, cs} -> Repo.rollback(cs)
    end
  end

  @doc """
  Declines a request with an optional parent note (max 500 chars).

  Transitions `:pending | :viewed` → `:declined`. Starts the 48-hour
  cooldown. Emits `request.declined` telemetry.
  """
  def decline(request_id, parent_note \\ nil, _attrs \\ %{}) do
    with %Request{} = request <- Repo.get(Request, request_id),
         true <- Request.pending?(request) do
      apply_decline(request, parent_note)
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_pending}
    end
  end

  defp apply_decline(request, parent_note) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    request
    |> Request.transition_changeset(%{
      status: :declined,
      decided_at: now,
      parent_note: parent_note
    })
    |> Repo.update()
    |> tap_on_ok(:declined)
  end

  defp tap_on_ok({:ok, updated}, event) do
    emit(event, updated)
    {:ok, updated}
  end

  defp tap_on_ok(error, _event), do: error

  @doc """
  Manually expires a request. Called by `RequestExpiryWorker` for any
  `:pending | :viewed` row past its `expires_at`.

  Emits `request.expired` telemetry.
  """
  def expire(request_id) do
    with %Request{} = request <- Repo.get(Request, request_id),
         true <- Request.pending?(request) do
      request
      |> Request.transition_changeset(%{status: :expired})
      |> Repo.update()
      |> tap_on_ok(:expired)
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_pending}
    end
  end

  @doc """
  Lists pending + viewed requests addressed to a guardian, newest first.
  Preloads the `:student` UserRole for rendering.
  """
  def list_pending_for_guardian(guardian_id) do
    from(r in Request,
      where: r.guardian_id == ^guardian_id and r.status in [:pending, :viewed],
      order_by: [desc: r.sent_at],
      preload: [:student]
    )
    |> Repo.all()
  end

  @doc "Counts `:pending | :viewed` requests for a student (0 or 1 by invariant)."
  def count_pending_for_student(student_id) do
    from(r in Request,
      where: r.student_id == ^student_id and r.status in [:pending, :viewed],
      select: count(r.id)
    )
    |> Repo.one()
  end

  @doc """
  Sends exactly one reminder for a request. Subsequent calls return
  `{:error, :already_reminded}`. Emits `request.reminded` telemetry on
  success.
  """
  def send_reminder(request_id) do
    case Repo.get(Request, request_id) do
      nil ->
        {:error, :not_found}

      %Request{reminder_sent_at: ts} when not is_nil(ts) ->
        {:error, :already_reminded}

      %Request{status: status} when status not in [:pending, :viewed] ->
        {:error, :not_pending}

      %Request{} = request ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        request
        |> Request.transition_changeset(%{reminder_sent_at: now})
        |> Repo.update()
        |> tap_on_ok(:reminded)
    end
  end

  @doc """
  Returns all `:pending | :viewed` requests whose `expires_at` is in the
  past. Used by `RequestExpiryWorker`.
  """
  def list_expired_pending do
    now = DateTime.utc_now()

    from(r in Request,
      where: r.status in [:pending, :viewed] and r.expires_at < ^now
    )
    |> Repo.all()
  end

  @doc """
  Builds a snapshot of a student's recent activity for the request
  metadata map. Used on creation (§4.6, §8.2).

  Shape:

      %{
        "streak_days" => 5,
        "weekly_minutes" => 95,
        "weekly_sessions" => 12,
        "accuracy_pct" => 82.5,
        "upcoming_test" => %{
          "name" => "Chem Unit 3",
          "date" => "2026-05-01",
          "days_away" => 9
        },  # or nil when none
        "captured_at" => "2026-04-22T15:04:05Z"
      }

  All numbers come from real activity data — never fabricated. A student
  with zero activity gets zeros, not placeholders.
  """
  def build_snapshot(student_id) do
    activity = StudySessions.parent_activity_summary(student_id)
    upcoming = next_upcoming_test(student_id)

    %{
      "streak_days" => activity.streak_count,
      "weekly_minutes" => activity.total_study_minutes_week,
      "weekly_sessions" => activity.sessions_this_week,
      "accuracy_pct" => activity.average_accuracy,
      "upcoming_test" => serialize_upcoming(upcoming),
      "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  ## Private helpers

  defp next_upcoming_test(student_id) do
    case Assessments.list_upcoming_schedules(student_id, 90) do
      [%{test_date: _} = schedule | _] -> schedule
      _ -> nil
    end
  end

  defp serialize_upcoming(nil), do: nil

  defp serialize_upcoming(%{name: name, test_date: date}) do
    %{
      "name" => name,
      "date" => Date.to_iso8601(date),
      "days_away" => Date.diff(date, Date.utc_today())
    }
  end

  defp ensure_no_recent_decline(student_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@decline_cooldown_hours * 3600, :second)

    exists =
      from(r in Request,
        where:
          r.student_id == ^student_id and
            r.status == :declined and
            r.decided_at >= ^cutoff
      )
      |> Repo.exists?()

    if exists, do: {:error, :decline_cooldown}, else: :ok
  end

  defp emit(event, request, extra \\ %{}) do
    :telemetry.execute(
      [:fun_sheep, :practice_request, event],
      %{count: 1},
      Map.merge(
        %{
          request_id: request.id,
          student_id: request.student_id,
          guardian_id: request.guardian_id,
          status: request.status
        },
        extra
      )
    )
  end

  @doc false
  # Type-narrowing aid for code that expects UserRole.t() directly.
  def get_student!(request_id) do
    Repo.get!(Request, request_id) |> Repo.preload(:student) |> Map.fetch!(:student)
  end

  @doc false
  def get_guardian!(request_id) do
    case Repo.get!(Request, request_id) |> Repo.preload(:guardian) do
      %Request{guardian: %UserRole{} = g} -> g
      _ -> nil
    end
  end
end
