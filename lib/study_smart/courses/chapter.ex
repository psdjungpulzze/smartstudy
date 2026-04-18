defmodule StudySmart.Courses.Chapter do
  @moduledoc """
  Schema for chapters within a course.

  Supports hierarchical structure via `parent_id` for sub-chapters.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chapters" do
    field :name, :string
    field :position, :integer

    belongs_to :course, StudySmart.Courses.Course

    has_many :sections, StudySmart.Courses.Section
    has_many :questions, StudySmart.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:name, :position, :course_id])
    |> validate_required([:name, :position, :course_id])
    |> foreign_key_constraint(:course_id)
  end
end
