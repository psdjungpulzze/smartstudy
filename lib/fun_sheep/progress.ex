defmodule FunSheep.Progress do
  @moduledoc """
  Real-time progress broadcasts for long-running user-triggered operations.

  See `.claude/rules/i/progress-feedback.md` and
  `docs/i/ui-design/progress-feedback.md` for the full rule and rationale.

  ## Shape

  Every broadcast is `{:progress, %FunSheep.Progress.Event{}}` on the topic
  returned by `topic/2`. Subjects should subscribe in `mount/3` (only when
  `connected?/1` is true) and pattern-match on `{:progress, event}` in
  `handle_info/2`.

  ## Topics

  Progress is scoped by a **subject type + subject id** pair so that
  unrelated subscribers do not collide. For example, regeneration progress
  broadcasts on `"progress:course:<course_id>"`; an admin bulk-import page
  might broadcast on `"progress:import:<import_id>"`.

  The existing `course:<id>` topic is intentionally NOT reused — it carries
  coarser pipeline signals consumed by different pages.
  """

  alias Phoenix.PubSub

  @pubsub FunSheep.PubSub

  @doc """
  Build a PubSub topic string for progress updates.

  ## Examples

      iex> FunSheep.Progress.topic(:course, "abc")
      "progress:course:abc"
  """
  @spec topic(atom(), term()) :: String.t()
  def topic(subject_type, subject_id)
      when is_atom(subject_type) and not is_nil(subject_id) do
    "progress:#{subject_type}:#{subject_id}"
  end

  @doc "Subscribe the caller to a progress topic."
  @spec subscribe(atom(), term()) :: :ok | {:error, term()}
  def subscribe(subject_type, subject_id) do
    PubSub.subscribe(@pubsub, topic(subject_type, subject_id))
  end

  @doc "Broadcast a raw `%Event{}` on its declared topic."
  @spec broadcast(FunSheep.Progress.Event.t()) :: :ok | {:error, term()}
  def broadcast(%FunSheep.Progress.Event{topic_type: t, topic_id: id} = event) do
    PubSub.broadcast(@pubsub, topic(t, id), {:progress, event})
  end

  @doc """
  Emit a phase-transition event. Use at the start of a phase.

  Resets within-phase progress counters. **Returns the updated event** so
  subsequent `tick/4` calls carry the current phase metadata — callers must
  rebind their event variable.
  """
  @spec phase(FunSheep.Progress.Event.t(), atom(), String.t(), pos_integer()) ::
          FunSheep.Progress.Event.t()
  def phase(%FunSheep.Progress.Event{} = base, phase, phase_label, phase_index) do
    updated = %{
      base
      | phase: phase,
        phase_label: phase_label,
        phase_index: phase_index,
        progress: %{current: 0, total: nil, unit: ""},
        status: :running,
        error: nil,
        updated_at: DateTime.utc_now()
    }

    broadcast(updated)
    updated
  end

  @doc """
  Emit a within-phase tick (e.g. per-item completion).

  Returns the updated event. The caller must pass the event as last returned
  from `phase/4` so the broadcast carries the current phase name, label, and
  index — otherwise the UI reverts to a stale phase.
  """
  @spec tick(
          FunSheep.Progress.Event.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) :: FunSheep.Progress.Event.t()
  def tick(%FunSheep.Progress.Event{} = base, current, total, unit) do
    updated = %{
      base
      | progress: %{current: current, total: total, unit: unit},
        status: :running,
        updated_at: DateTime.utc_now()
    }

    broadcast(updated)
    updated
  end

  @doc "Emit a terminal success event. Returns the terminal event."
  @spec succeeded(FunSheep.Progress.Event.t(), String.t(), non_neg_integer()) ::
          FunSheep.Progress.Event.t()
  def succeeded(%FunSheep.Progress.Event{} = base, unit, final_count) do
    updated = %{
      base
      | phase: :done,
        phase_label: "Complete",
        progress: %{current: final_count, total: final_count, unit: unit},
        status: :succeeded,
        error: nil,
        updated_at: DateTime.utc_now()
    }

    broadcast(updated)
    updated
  end

  @doc "Emit a terminal failure event with a user-facing message. Returns the terminal event."
  @spec failed(FunSheep.Progress.Event.t(), atom(), String.t()) ::
          FunSheep.Progress.Event.t()
  def failed(%FunSheep.Progress.Event{} = base, code, message) do
    updated = %{
      base
      | phase: :failed,
        phase_label: "Failed",
        status: :failed,
        error: %{code: code, message: message},
        updated_at: DateTime.utc_now()
    }

    broadcast(updated)
    updated
  end
end
