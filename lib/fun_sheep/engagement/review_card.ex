defmodule FunSheep.Engagement.ReviewCard do
  @moduledoc """
  Schema for spaced repetition review cards.

  Each card tracks a question's review schedule using the SM-2 algorithm.
  Cards progress through: new → learning → review → graduated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(new learning review graduated)

  schema "review_cards" do
    field :ease_factor, :float, default: 2.5
    field :interval_days, :float, default: 0.0
    field :repetitions, :integer, default: 0
    field :next_review_at, :utc_datetime
    field :last_reviewed_at, :utc_datetime
    field :status, :string, default: "new"

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :question, FunSheep.Questions.Question
    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      :ease_factor,
      :interval_days,
      :repetitions,
      :next_review_at,
      :last_reviewed_at,
      :status,
      :user_role_id,
      :question_id,
      :course_id
    ])
    |> validate_required([:user_role_id, :question_id, :course_id, :next_review_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:ease_factor, greater_than_or_equal_to: 1.3)
    |> validate_number(:interval_days, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_role_id, :question_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:question_id)
    |> foreign_key_constraint(:course_id)
  end
end
