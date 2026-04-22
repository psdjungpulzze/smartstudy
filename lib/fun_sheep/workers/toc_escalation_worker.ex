defmodule FunSheep.Workers.TOCEscalationWorker do
  @moduledoc """
  Daily scheduled worker that closes the loop on pending TOC proposals
  that nobody has acted on.

  The community-approval tiers in `Courses.TOCRebase`:

    * 0–7d since proposal → creator (or active uploader) can approve
    * 7–14d → any active user can approve
    * 14d+ → admin fallback, OR auto-apply if still attempts-safe

  This worker runs once a day. For every course with a pending proposal
  older than 14 days:

    * If the rebase is still attempts-safe → auto-apply it so courses
      don't sit in limbo forever. (Same safety check as `decide_action/3`.)
    * Otherwise → leave the pending state alone; admin workflow will
      surface it (eventually via an admin dashboard — deferred).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias FunSheep.Courses.{Course, DiscoveredTOC, TOCRebase}
  alias FunSheep.Repo

  require Logger

  # Any pending older than this gets the escalation treatment.
  @admin_window_days 14

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@admin_window_days * 24 * 60 * 60, :second)

    # Match two cases that both need cleanup:
    #   1. pending_toc_id + proposed_at set and older than cutoff → usual
    #      escalation path.
    #   2. pending_toc_id is nil (the TOC row was deleted, cascade
    #      nilified the FK) but proposed_at lingers — data-integrity
    #      cleanup so later queries see consistent state.
    stale =
      from(c in Course,
        where:
          not is_nil(c.pending_toc_proposed_at) and
            c.pending_toc_proposed_at <= ^cutoff
      )
      |> Repo.all()

    Enum.each(stale, &escalate/1)

    Logger.info("[TOCEscalation] Processed #{length(stale)} stale proposals (>14d)")
    :ok
  end

  defp escalate(%Course{pending_toc_id: nil} = course) do
    # TOC was deleted out from under us — nothing to apply, just clean
    # the lingering proposed_at timestamp.
    {:ok, _} = TOCRebase.clear_pending(course)
    :ok
  end

  defp escalate(%Course{} = course) do
    case Repo.get(DiscoveredTOC, course.pending_toc_id) do
      nil ->
        # Pending points at a deleted row — clear it.
        {:ok, _} = TOCRebase.clear_pending(course)
        :ok

      %DiscoveredTOC{} = toc ->
        maybe_auto_apply_stale(course, toc)
    end
  end

  # Re-run the attempts-safety gate — stale proposals can become unsafe
  # if new students started attempting questions since the proposal was
  # made. If still safe, apply. If not, leave alone; admin surfaces it.
  defp maybe_auto_apply_stale(%Course{} = course, %DiscoveredTOC{} = toc) do
    current = TOCRebase.current(course.id)
    decision = TOCRebase.decide_action(toc, current, course.pending_toc_proposed_by_id)

    case decision do
      :auto_apply ->
        do_apply(course, toc, "fell through admin window, still safe")

      {:pending, :needs_admin_approval} ->
        # Leave it — admin dashboard surfaces it.
        Logger.info(
          "[TOCEscalation] Course #{course.id} pending proposal needs admin " <>
            "(not safe to auto-apply): toc=#{toc.id}"
        )

      _other ->
        # Decision says it's no longer a material improvement (e.g.,
        # another TOC applied since then). Clear the pending.
        {:ok, _} = TOCRebase.clear_pending(course)
        Logger.info("[TOCEscalation] Cleared stale pending on course #{course.id}")
    end
  end

  defp do_apply(course, toc, reason) do
    case TOCRebase.approve!(course, toc) do
      {:ok, stats} ->
        # Eagerly fill new chapters — same pattern as EnrichDiscoveryWorker.
        Enum.each(stats.new_chapter_ids, fn chapter_id ->
          FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course.id,
            chapter_id: chapter_id,
            count: 10,
            mode: "from_material"
          )
        end)

        Logger.info(
          "[TOCEscalation] Auto-applied #{course.id} (#{reason}): " <>
            "kept=#{stats.kept} created=#{stats.created} " <>
            "orphaned=#{stats.orphaned} deleted=#{stats.deleted}"
        )

      {:error, error_reason} ->
        Logger.error("[TOCEscalation] Apply failed for #{course.id}: #{inspect(error_reason)}")
    end
  end

  @doc """
  Config to register this worker on Oban's cron plugin. Caller in
  `config/*.exs` adds `{"0 8 * * *", FunSheep.Workers.TOCEscalationWorker}` —
  runs once a day at 08:00 UTC.
  """
  def cron_schedule, do: "0 8 * * *"
end
