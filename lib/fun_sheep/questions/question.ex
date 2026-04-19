defmodule FunSheep.Questions.Question do
  @moduledoc """
  Schema for the central question bank.

  Questions are tagged by chapter, school, source, and whether they
  were AI-generated. Hobby context tracks personalization used during generation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "questions" do
    field :content, :string
    field :answer, :string

    field :question_type, Ecto.Enum,
      values: [:multiple_choice, :short_answer, :free_response, :true_false]

    field :options, :map
    field :source_url, :string
    field :source_page, :integer
    field :is_generated, :boolean, default: false
    field :hobby_context, :string
    field :difficulty, Ecto.Enum, values: [:easy, :medium, :hard]
    field :metadata, :map, default: %{}

    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :section, FunSheep.Courses.Section
    belongs_to :school, FunSheep.Geo.School
    belongs_to :source_material, FunSheep.Content.UploadedMaterial

    has_many :question_attempts, FunSheep.Questions.QuestionAttempt
    has_one :stats, FunSheep.Questions.QuestionStats

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :content,
      :answer,
      :question_type,
      :options,
      :source_url,
      :source_page,
      :is_generated,
      :hobby_context,
      :difficulty,
      :metadata,
      :course_id,
      :chapter_id,
      :section_id,
      :school_id,
      :source_material_id
    ])
    |> validate_required([:content, :answer, :question_type, :difficulty, :course_id])
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:chapter_id)
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:school_id)
  end
end
