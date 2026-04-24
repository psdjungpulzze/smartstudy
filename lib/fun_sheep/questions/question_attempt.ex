defmodule FunSheep.Questions.QuestionAttempt do
  @moduledoc """
  Schema for recording student answers to questions.

  Each attempt captures the answer given, correctness,
  time taken, and difficulty at the time of the attempt.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "question_attempts" do
    field :answer_given, :string
    field :is_correct, :boolean
    field :time_taken_seconds, :integer
    field :difficulty_at_attempt, :string
    # Essay-specific fields
    field :essay_draft_id, :binary_id
    field :essay_word_count, :integer

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :question, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question_attempt, attrs) do
    question_attempt
    |> cast(attrs, [
      :answer_given,
      :is_correct,
      :time_taken_seconds,
      :difficulty_at_attempt,
      :user_role_id,
      :question_id,
      :essay_draft_id,
      :essay_word_count
    ])
    |> validate_required([:is_correct, :user_role_id, :question_id])
    |> validate_number(:time_taken_seconds, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:question_id)
  end
end
