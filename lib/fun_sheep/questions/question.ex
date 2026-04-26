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
      values: [
        :multiple_choice,
        :short_answer,
        :free_response,
        :true_false,
        :essay,
        :multi_select,
        :cloze,
        :matching,
        :ordering,
        :numeric
      ]

    field :options, :map
    field :source_url, :string
    field :source_page, :integer
    field :is_generated, :boolean, default: false
    field :hobby_context, :string
    field :difficulty, Ecto.Enum, values: [:easy, :medium, :hard]
    field :metadata, :map, default: %{}
    field :explanation, :string

    # Phase 1 unified provenance. Replaces the scattered combination of
    # `is_generated`, `source_url`, `source_material_id`, and
    # `metadata["source"]`. Those remain for one release while callers
    # migrate, then drop in a follow-up.
    field :source_type, Ecto.Enum, values: [:web_scraped, :user_uploaded, :ai_generated, :curated]

    # For :ai_generated rows, the grounding strategy the worker used.
    # Typical values: "from_curriculum", "from_material", "from_web_context".
    # Free-form string so workers can introduce new modes without a
    # migration. `nil` on non-AI rows.
    field :generation_mode, :string

    # List of grounding references that fed the generator/extractor prompt.
    # Shape: %{"refs" => [%{"type" => "material"|"url"|"discovered_source",
    #                       "id" => uuid_or_url}]}.
    # Load-bearing for Phase 6 coverage audits and Phase 8 admin UI.
    field :grounding_refs, :map, default: %{}

    field :validation_status, Ecto.Enum,
      values: [:pending, :passed, :needs_review, :failed],
      default: :pending

    field :validation_score, :float
    field :validation_report, :map, default: %{}
    field :validated_at, :utc_datetime
    # Counts batches the validator could not parse for this question.
    # The worker increments on parse_failed and gives up at @max_validation_attempts
    # to break the zombie loop where unparseable LLM output keeps re-enqueueing.
    field :validation_attempts, :integer, default: 0

    field :classification_status, Ecto.Enum,
      values: [:uncategorized, :ai_classified, :admin_reviewed, :low_confidence],
      default: :uncategorized

    field :classification_confidence, :float
    field :classified_at, :utc_datetime

    # Essay-specific fields — only set for question_type: :essay
    field :essay_time_limit_minutes, :integer
    field :essay_word_target, :integer
    field :essay_word_limit, :integer
    # Array of %{"title" => ..., "body" => ...} for DBQ/synthesis prompts
    field :essay_source_documents, :map

    # Comprehension group fields — set when question belongs to a stimulus group
    field :group_sequence, :integer

    # SHA-256 fingerprint of normalized content — used for web-scraped
    # deduplication (partial unique index on course_id + fingerprint).
    field :content_fingerprint, :string

    # Trust tier of the web source (1–4 per FunSheep.Scraper.SourceReputation).
    # nil for AI-generated questions. Used to apply per-tier validation thresholds
    # so questions from official test makers (tier 1) aren't unfairly rejected.
    field :source_tier, :integer

    belongs_to :essay_rubric_template, FunSheep.Essays.EssayRubricTemplate
    belongs_to :question_group, FunSheep.Questions.QuestionGroup
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :section, FunSheep.Courses.Section
    belongs_to :school, FunSheep.Geo.School
    belongs_to :source_material, FunSheep.Content.UploadedMaterial

    has_many :question_attempts, FunSheep.Questions.QuestionAttempt
    has_one :stats, FunSheep.Questions.QuestionStats

    many_to_many :figures, FunSheep.Content.SourceFigure,
      join_through: FunSheep.Questions.QuestionFigure,
      join_keys: [question_id: :id, source_figure_id: :id],
      on_replace: :delete

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
      :explanation,
      :source_type,
      :generation_mode,
      :grounding_refs,
      :validation_status,
      :validation_score,
      :validation_report,
      :validated_at,
      :validation_attempts,
      :classification_status,
      :classification_confidence,
      :classified_at,
      :course_id,
      :chapter_id,
      :section_id,
      :school_id,
      :source_material_id,
      :essay_rubric_template_id,
      :essay_time_limit_minutes,
      :essay_word_target,
      :essay_word_limit,
      :essay_source_documents,
      :question_group_id,
      :group_sequence,
      :content_fingerprint,
      :source_tier
    ])
    |> validate_required([:content, :answer, :question_type, :difficulty, :course_id])
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:chapter_id)
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:school_id)
    |> foreign_key_constraint(:essay_rubric_template_id)
    |> foreign_key_constraint(:question_group_id)
  end
end
