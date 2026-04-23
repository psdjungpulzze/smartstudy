defmodule FunSheep.Progress.Event do
  @moduledoc """
  Standard shape for a progress update broadcast.

  Matches the contract in `docs/i/ui-design/progress-feedback.md`. Subjects
  build a base event once (per job) via `new/1` and then emit phase / tick /
  terminal updates with helpers in `FunSheep.Progress`.
  """

  @enforce_keys [
    :job_id,
    :topic_type,
    :topic_id,
    :scope,
    :phase,
    :phase_label,
    :phase_index,
    :phase_total,
    :started_at,
    :updated_at,
    :status
  ]
  defstruct [
    :job_id,
    :topic_type,
    :topic_id,
    :scope,
    :phase,
    :phase_label,
    :phase_index,
    :phase_total,
    :detail,
    :subject_id,
    :subject_label,
    :progress,
    :eta_seconds,
    :error,
    :started_at,
    :updated_at,
    :status
  ]

  @type status :: :queued | :running | :succeeded | :failed | :partial

  @type progress_map :: %{
          current: non_neg_integer(),
          total: non_neg_integer() | nil,
          unit: String.t()
        }

  @type error_map :: %{code: atom(), message: String.t()}

  @type t :: %__MODULE__{
          job_id: String.t(),
          topic_type: atom(),
          topic_id: term(),
          scope: atom(),
          phase: atom(),
          phase_label: String.t(),
          phase_index: pos_integer(),
          phase_total: pos_integer(),
          detail: String.t() | nil,
          subject_id: String.t() | nil,
          subject_label: String.t() | nil,
          progress: progress_map() | nil,
          eta_seconds: non_neg_integer() | nil,
          error: error_map() | nil,
          started_at: DateTime.t(),
          updated_at: DateTime.t(),
          status: status()
        }

  @doc """
  Build a base event for a new job.

  Required opts: `:job_id`, `:topic_type`, `:topic_id`, `:scope`,
  `:phase_total`. Optional: `:subject_id`, `:subject_label`, `:detail`.

  The returned event is in a pre-started state (`phase: :queued`). Callers
  should then emit `Progress.phase/4` when real work begins.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    now = DateTime.utc_now()

    %__MODULE__{
      job_id: Keyword.fetch!(opts, :job_id),
      topic_type: Keyword.fetch!(opts, :topic_type),
      topic_id: Keyword.fetch!(opts, :topic_id),
      scope: Keyword.fetch!(opts, :scope),
      phase: :queued,
      phase_label: Keyword.get(opts, :phase_label, "Queued"),
      phase_index: 0,
      phase_total: Keyword.fetch!(opts, :phase_total),
      detail: Keyword.get(opts, :detail),
      subject_id: Keyword.get(opts, :subject_id),
      subject_label: Keyword.get(opts, :subject_label),
      progress: %{current: 0, total: nil, unit: ""},
      eta_seconds: nil,
      error: nil,
      started_at: now,
      updated_at: now,
      status: :queued
    }
  end

  @doc "Returns true when the event represents a terminal state."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}) when status in [:succeeded, :failed, :partial],
    do: true

  def terminal?(_), do: false
end
