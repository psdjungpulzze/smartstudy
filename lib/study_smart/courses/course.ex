defmodule StudySmart.Courses.Course do
  @moduledoc """
  Schema for courses (subjects) in StudySmart.

  A course represents a subject at a specific grade level,
  optionally associated with a school.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "courses" do
    field :name, :string
    field :subject, :string
    field :grade, :string
    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :school, StudySmart.Geo.School
    belongs_to :created_by, StudySmart.Accounts.UserRole

    has_many :chapters, StudySmart.Courses.Chapter
    has_many :questions, StudySmart.Questions.Question
    has_many :uploaded_materials, StudySmart.Content.UploadedMaterial
    has_many :test_schedules, StudySmart.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [:name, :subject, :grade, :description, :metadata, :school_id, :created_by_id])
    |> validate_required([:name, :subject, :grade])
    |> foreign_key_constraint(:school_id)
  end
end
