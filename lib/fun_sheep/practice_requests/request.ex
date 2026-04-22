defmodule FunSheep.PracticeRequests.Request do
  @moduledoc """
  A student's request for their guardian to unlock unlimited practice.

  See `~/s/funsheep-subscription-flows.md` §4 (Flow A) and §7.1.

  Lifecycle: `:pending` → (`:viewed`?) → `:accepted | :declined | :expired | :cancelled`.
  A student may have at most one `:pending` request at a time, enforced by
  the partial unique index `practice_requests_one_pending_per_student`.

  The `metadata` map is an immutable snapshot of student activity taken at
  send time — streak, weekly minutes, weekly questions, accuracy, upcoming
  test — so parent emails render from stable data even if activity drifts.
  Per CLAUDE.md absolute rule: every field here must come from real
  activity, never fabricated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reason_codes ~w(upcoming_test weak_topic streak other)a
  @statuses ~w(pending viewed accepted declined expired cancelled)a

  # §4.5 — requests auto-expire after 7 days.
  @ttl_days 7

  schema "practice_requests" do
    field :reason_code, Ecto.Enum, values: @reason_codes
    field :reason_text, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    field :sent_at, :utc_datetime
    field :viewed_at, :utc_datetime
    field :decided_at, :utc_datetime
    field :expires_at, :utc_datetime

    field :parent_note, :string
    field :reminder_sent_at, :utc_datetime

    field :metadata, :map, default: %{}

    belongs_to :student, FunSheep.Accounts.UserRole
    belongs_to :guardian, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new request from a student.

  Stamps `sent_at`, `expires_at` (sent_at + 7d), and defaults `status` to
  `:pending` if not provided.
  """
  def create_changeset(request, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    request
    |> cast(attrs, [
      :student_id,
      :guardian_id,
      :reason_code,
      :reason_text,
      :metadata
    ])
    |> put_change(:status, :pending)
    |> put_change(:sent_at, now)
    |> put_change(:expires_at, DateTime.add(now, @ttl_days, :day))
    |> validate_required([:student_id, :reason_code, :metadata])
    |> validate_reason_text()
    |> validate_length(:reason_text, max: 140)
    |> foreign_key_constraint(:student_id)
    |> foreign_key_constraint(:guardian_id)
    |> unique_constraint(:student_id,
      name: :practice_requests_one_pending_per_student,
      message: "already has a pending request"
    )
  end

  @doc """
  Changeset for state transitions (:viewed, :accepted, :declined, :expired, :cancelled).

  Callers stamp the appropriate timestamp(s) and optional `parent_note`.
  """
  def transition_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :viewed_at,
      :decided_at,
      :parent_note,
      :reminder_sent_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:parent_note, max: 500)
  end

  @doc "Returns true if the request is past its expiry timestamp."
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc "Returns true if the request is open for a parent decision."
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{status: :viewed}), do: true
  def pending?(_), do: false

  @doc "The list of valid reason codes (for UI pickers and validations)."
  def reason_codes, do: @reason_codes

  @doc "The list of valid statuses."
  def statuses, do: @statuses

  @doc "Days until auto-expiry from `sent_at`."
  def ttl_days, do: @ttl_days

  defp validate_reason_text(changeset) do
    case get_field(changeset, :reason_code) do
      :other ->
        validate_required(changeset, [:reason_text], message: "is required when reason is Other")

      _ ->
        changeset
    end
  end
end
