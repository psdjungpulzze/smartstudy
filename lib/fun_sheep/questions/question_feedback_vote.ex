defmodule FunSheep.Questions.QuestionFeedbackVote do
  @moduledoc """
  Per-user, per-question feedback vote.

  A user can cast exactly one vote per question (like or dislike). They may
  additionally attach a flag reason to indicate a specific content problem.
  The flag reason is stored independently of the vote direction so a user
  can dislike AND explain why in one record.

  Dislikes are weighted 3× in quality score computation — explicit negative
  feedback requires deliberate effort and is therefore a stronger quality signal.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @votes [:like, :dislike]
  @flag_reasons [:incorrect_answer, :unclear, :outdated, :inappropriate]

  schema "question_feedback_votes" do
    field :vote, Ecto.Enum, values: @votes
    field :flag_reason, Ecto.Enum, values: @flag_reasons

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :question, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  def votes, do: @votes
  def flag_reasons, do: @flag_reasons

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:vote, :flag_reason, :user_role_id, :question_id])
    |> validate_required([:vote, :user_role_id, :question_id])
    |> validate_inclusion(:vote, @votes)
    |> validate_inclusion(:flag_reason, @flag_reasons ++ [nil])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:question_id)
    |> unique_constraint([:user_role_id, :question_id],
      name: :question_feedback_votes_user_role_id_question_id_index,
      message: "already voted on this question"
    )
  end
end
