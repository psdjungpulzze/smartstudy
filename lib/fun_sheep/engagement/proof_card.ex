defmodule FunSheep.Engagement.ProofCard do
  @moduledoc """
  Schema for shareable progress snapshots ("Proof Cards").

  Generated at milestones (readiness jumps, streak achievements, etc.)
  and shareable via unique token for parent-to-parent viral distribution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @card_types ~w(readiness_jump streak_milestone weekly_rank test_complete session_receipt)

  schema "proof_cards" do
    field :card_type, :string
    field :title, :string
    field :metrics, :map, default: %{}
    field :share_token, :string
    field :shared_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :test_schedule, FunSheep.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      :card_type,
      :title,
      :metrics,
      :share_token,
      :shared_at,
      :user_role_id,
      :course_id,
      :test_schedule_id
    ])
    |> validate_required([:card_type, :title, :metrics, :share_token, :user_role_id])
    |> validate_inclusion(:card_type, @card_types)
    |> unique_constraint(:share_token)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:test_schedule_id)
  end

  @doc "Generates a unique share token."
  def generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
