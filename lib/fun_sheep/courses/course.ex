defmodule FunSheep.Courses.Course do
  @moduledoc """
  Schema for courses (subjects) in FunSheep.

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
    field :processing_status, :string, default: "pending"
    field :processing_step, :string
    field :processing_error, :string
    field :ocr_completed_count, :integer, default: 0
    field :ocr_total_count, :integer, default: 0
    field :custom_textbook_name, :string

    belongs_to :school, FunSheep.Geo.School
    belongs_to :created_by, FunSheep.Accounts.UserRole
    belongs_to :textbook, FunSheep.Courses.Textbook

    has_many :chapters, FunSheep.Courses.Chapter
    has_many :questions, FunSheep.Questions.Question
    has_many :uploaded_materials, FunSheep.Content.UploadedMaterial
    has_many :test_schedules, FunSheep.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :name,
      :subject,
      :grade,
      :description,
      :metadata,
      :school_id,
      :created_by_id,
      :processing_status,
      :processing_step,
      :processing_error,
      :ocr_completed_count,
      :ocr_total_count,
      :textbook_id,
      :custom_textbook_name
    ])
    |> validate_required([:name, :subject, :grade])
    |> foreign_key_constraint(:school_id)
  end
end
