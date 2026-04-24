defmodule FunSheep.Enrollments.StudentCourse do
  @moduledoc """
  Schema for student course enrollments.

  Tracks which courses a student is enrolled in, when they enrolled,
  the enrollment source, and the current status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active dropped completed)
  @sources ~w(self_enrolled onboarding guardian_assigned teacher_assigned)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "student_courses" do
    field :status, :string, default: "active"
    field :enrolled_at, :utc_datetime
    field :source, :string, default: "self_enrolled"

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  def changeset(student_course, attrs) do
    student_course
    |> cast(attrs, [:user_role_id, :course_id, :status, :enrolled_at, :source])
    |> validate_required([:user_role_id, :course_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:user_role_id, :course_id])
  end
end
