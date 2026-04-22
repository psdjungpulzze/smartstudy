defmodule FunSheep.Assessments.TestSchedule do
  @moduledoc """
  Schema for scheduled tests.

  Links a student to a course with a test date, scope (chapters/topics),
  and optional format template.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "test_schedules" do
    field :name, :string
    field :test_date, :date
    field :scope, :map
    field :external_provider, :string
    field :external_id, :string
    field :external_synced_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :format_template, FunSheep.Assessments.TestFormatTemplate

    has_many :readiness_scores, FunSheep.Assessments.ReadinessScore
    has_many :study_guides, FunSheep.Learning.StudyGuide

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(test_schedule, attrs) do
    test_schedule
    |> cast(attrs, [
      :name,
      :test_date,
      :scope,
      :user_role_id,
      :course_id,
      :format_template_id,
      :external_provider,
      :external_id,
      :external_synced_at
    ])
    |> validate_required([:name, :test_date, :scope, :user_role_id, :course_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:format_template_id)
  end
end
