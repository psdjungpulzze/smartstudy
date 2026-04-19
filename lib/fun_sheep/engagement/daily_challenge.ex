defmodule FunSheep.Engagement.DailyChallenge do
  @moduledoc """
  Schema for daily challenges ("Daily Shear").

  One challenge per course per day with 5 shared questions.
  All students in the same course get the same questions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "daily_challenges" do
    field :challenge_date, :date
    field :question_ids, {:array, :binary_id}, default: []
    field :metadata, :map, default: %{}

    belongs_to :course, FunSheep.Courses.Course
    has_many :attempts, FunSheep.Engagement.DailyChallengeAttempt

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:challenge_date, :question_ids, :course_id, :metadata])
    |> validate_required([:challenge_date, :question_ids, :course_id])
    |> validate_length(:question_ids, min: 1, max: 10)
    |> unique_constraint([:challenge_date, :course_id])
    |> foreign_key_constraint(:course_id)
  end
end
