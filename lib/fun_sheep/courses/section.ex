defmodule FunSheep.Courses.Section do
  @moduledoc """
  Schema for sections within a chapter.

  Sections represent the finest granularity of course structure.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sections" do
    field :name, :string
    field :position, :integer

    belongs_to :chapter, FunSheep.Courses.Chapter
    has_many :questions, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:name, :position, :chapter_id])
    |> validate_required([:name, :position, :chapter_id])
    |> foreign_key_constraint(:chapter_id)
  end
end
