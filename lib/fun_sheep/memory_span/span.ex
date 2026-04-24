defmodule FunSheep.MemorySpan.Span do
  @moduledoc """
  Schema for memory span records.

  A memory span records how long a student's memory lasts for a given
  granularity (question, chapter, or course) before they forget and answer
  incorrectly. The span_hours is the median gap in hours between a correct
  answer and a subsequent incorrect answer (a "decay event").

  Trend tracks whether retention is improving, declining, or stable
  compared to the previous calculation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memory_spans" do
    field :granularity, :string
    field :span_hours, :integer
    field :decay_event_count, :integer, default: 0
    field :trend, :string
    field :previous_span_hours, :integer
    field :calculated_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :question, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(span, attrs) do
    span
    |> cast(attrs, [
      :user_role_id,
      :course_id,
      :chapter_id,
      :question_id,
      :granularity,
      :span_hours,
      :decay_event_count,
      :trend,
      :previous_span_hours,
      :calculated_at
    ])
    |> validate_required([:user_role_id, :course_id, :granularity, :calculated_at])
    |> validate_inclusion(:granularity, ["question", "chapter", "course"])
    |> validate_number(:decay_event_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:chapter_id)
    |> foreign_key_constraint(:question_id)
  end
end
