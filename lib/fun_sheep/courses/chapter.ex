defmodule FunSheep.Courses.Chapter do
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
    # Set by TOCRebase when a chapter was preserved through a rebase because
    # it carried student attempts but didn't match any chapter in the new
    # TOC. Surfaces these to admins as "not in current textbook structure".
    field :orphaned_at, :utc_datetime

    belongs_to :course, FunSheep.Courses.Course

    has_many :sections, FunSheep.Courses.Section
    has_many :questions, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:name, :position, :course_id, :orphaned_at])
    |> validate_required([:name, :position, :course_id])
    |> foreign_key_constraint(:course_id)
  end
end
