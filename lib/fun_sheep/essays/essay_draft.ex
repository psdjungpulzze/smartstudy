defmodule FunSheep.Essays.EssayDraft do
  @moduledoc """
  Schema for essay drafts.

  Tracks the student's in-progress and submitted essay for a specific
  question (optionally scoped to a test schedule). Only one active
  (non-submitted) draft may exist per (user_role_id, question_id,
  schedule_id) triple.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "essay_drafts" do
    field :body, :string
    field :word_count, :integer, default: 0
    field :last_saved_at, :utc_datetime
    field :started_at, :utc_datetime
    field :time_elapsed_seconds, :integer, default: 0
    field :submitted, :boolean, default: false
    field :submitted_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :question, FunSheep.Questions.Question
    # nullable — when nil the draft is for standalone practice, not a timed test
    field :schedule_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [
      :user_role_id,
      :question_id,
      :schedule_id,
      :body,
      :word_count,
      :last_saved_at,
      :started_at,
      :time_elapsed_seconds,
      :submitted,
      :submitted_at
    ])
    |> validate_required([:user_role_id, :question_id, :last_saved_at, :started_at])
    |> validate_number(:word_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:question_id)
    |> unique_constraint([:user_role_id, :question_id, :schedule_id])
  end
end
