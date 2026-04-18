defmodule FunSheep.Assessments.TestFormatTemplate do
  @moduledoc """
  Schema for test format templates.

  Stores the structure of a test format (sections, question types,
  counts, time limits) analyzed from an uploaded sample.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "test_format_templates" do
    field :name, :string
    field :structure, :map

    belongs_to :course, FunSheep.Courses.Course
    belongs_to :created_by, FunSheep.Accounts.UserRole

    has_many :test_schedules, FunSheep.Assessments.TestSchedule,
      foreign_key: :format_template_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(test_format_template, attrs) do
    test_format_template
    |> cast(attrs, [:name, :structure, :course_id, :created_by_id])
    |> validate_required([:name, :structure])
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
