defmodule FunSheep.Accountability.PracticeAssignment do
  @moduledoc """
  Parent-initiated practice assignment (spec §7.2).

  Bounded by design: max 20 questions per assignment and max 3 open
  assignments per student (enforced in the `Accountability` context).

  Questions are resolved at session-start time via the existing practice
  engine — we do **not** denormalise a question list into this table
  because topics mutate and difficulty adapts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :in_progress, :completed, :expired]
  @max_questions 20

  schema "practice_assignments" do
    field :question_count, :integer
    field :due_date, :date
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :completed_at, :utc_datetime
    field :questions_attempted, :integer, default: 0
    field :questions_correct, :integer, default: 0

    belongs_to :student, FunSheep.Accounts.UserRole
    belongs_to :guardian, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :section, FunSheep.Courses.Section

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def max_questions, do: @max_questions

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [
      :student_id,
      :guardian_id,
      :course_id,
      :chapter_id,
      :section_id,
      :question_count,
      :due_date,
      :status,
      :completed_at,
      :questions_attempted,
      :questions_correct
    ])
    |> validate_required([:student_id, :guardian_id, :question_count, :status])
    |> validate_number(:question_count,
      greater_than: 0,
      less_than_or_equal_to: @max_questions
    )
    |> foreign_key_constraint(:student_id)
    |> foreign_key_constraint(:guardian_id)
  end
end
