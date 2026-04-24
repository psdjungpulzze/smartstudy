defmodule FunSheep.Questions.QuestionGroup do
  @moduledoc """
  A stimulus (reading passage, data set, clinical vignette, etc.) that anchors
  a set of related questions. Questions in the group share the same source
  material and are presented together during comprehension practice.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stimulus_types [
    :reading_passage,
    :data_set,
    :clinical_vignette,
    :science_passage,
    :primary_sources,
    :synthesis_sources,
    :dual_passage,
    :audio_transcript
  ]
  @difficulties [:easy, :medium, :hard]
  @source_types [:web_scraped, :user_uploaded, :ai_generated, :curated]
  @validation_statuses [:pending, :passed, :needs_review, :failed]

  schema "question_groups" do
    field :stimulus_type, Ecto.Enum, values: @stimulus_types
    field :stimulus_title, :string
    field :stimulus_content, :string
    field :stimulus_html, :string
    field :word_count, :integer
    field :reading_level, :string
    field :difficulty, Ecto.Enum, values: @difficulties
    field :source_type, Ecto.Enum, values: @source_types, default: :ai_generated
    field :generation_mode, :string
    field :grounding_refs, :map, default: %{}
    field :validation_status, Ecto.Enum, values: @validation_statuses, default: :pending
    field :validation_score, :float
    field :validation_report, :map, default: %{}
    field :validated_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :section, FunSheep.Courses.Section
    belongs_to :source_material, FunSheep.Content.UploadedMaterial

    has_many :questions, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [
      :stimulus_type,
      :stimulus_title,
      :stimulus_content,
      :stimulus_html,
      :word_count,
      :reading_level,
      :difficulty,
      :source_type,
      :generation_mode,
      :grounding_refs,
      :validation_status,
      :validation_score,
      :validation_report,
      :validated_at,
      :metadata,
      :course_id,
      :chapter_id,
      :section_id,
      :source_material_id
    ])
    |> validate_required([:stimulus_type, :stimulus_content])
    |> validate_length(:stimulus_content, min: 50)
    |> put_word_count()
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:chapter_id)
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:source_material_id)
  end

  defp put_word_count(changeset) do
    case get_change(changeset, :stimulus_content) do
      nil ->
        changeset

      content ->
        word_count = content |> String.split() |> length()
        put_change(changeset, :word_count, word_count)
    end
  end
end
