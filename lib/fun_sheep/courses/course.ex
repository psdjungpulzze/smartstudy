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
    field :external_provider, :string
    field :external_id, :string
    field :external_synced_at, :utc_datetime

    # Premium catalog fields
    # "public", "preview", "standard", "premium", "professional"
    field :access_level, :string, default: "public"
    field :is_premium_catalog, :boolean, default: false
    # 'sat', 'act', 'ap', 'ib', 'hsc', 'clt', 'lsat', 'bar', 'gmat', 'mcat', 'gre'
    field :catalog_test_type, :string
    # 'mathematics', 'biology', 'english_language', etc.
    field :catalog_subject, :string
    # 'hl', 'sl', 'ab', 'bc', '1', '2', etc.
    field :catalog_level, :string
    field :published_at, :utc_datetime
    field :sample_question_count, :integer, default: 10

    # Community quality scoring fields (Phase 1 — community content validation)
    field :quality_score, :float, default: 0.0
    field :like_count, :integer, default: 0
    field :dislike_count, :integer, default: 0
    field :completion_count, :integer, default: 0
    field :attempt_count, :integer, default: 0
    field :unique_user_count, :integer, default: 0
    field :quality_last_computed_at, :utc_datetime
    # "boosted", "normal", "reduced", "flagged", "pending_review", "delisted"
    field :visibility_state, :string, default: "normal"
    field :dormant_at, :utc_datetime


    # A TOC rebase proposal waiting for approval. When non-nil, the course
    # has a candidate DiscoveredTOC that didn't auto-apply (material change
    # with risk to existing attempts). UI surfaces this as a banner to the
    # creator / active users; escalates through tiers over time.
    field :ocr_started_at, :utc_datetime
    field :pending_toc_proposed_at, :utc_datetime

    belongs_to :school, FunSheep.Geo.School
    belongs_to :created_by, FunSheep.Accounts.UserRole
    belongs_to :textbook, FunSheep.Courses.Textbook
    belongs_to :pending_toc, FunSheep.Courses.DiscoveredTOC
    belongs_to :pending_toc_proposed_by, FunSheep.Accounts.UserRole
    belongs_to :published_by, FunSheep.Accounts.UserRole, foreign_key: :published_by_id

    has_many :chapters, FunSheep.Courses.Chapter
    has_many :questions, FunSheep.Questions.Question
    has_many :uploaded_materials, FunSheep.Content.UploadedMaterial
    has_many :test_schedules, FunSheep.Assessments.TestSchedule
    has_many :discovered_tocs, FunSheep.Courses.DiscoveredTOC
    has_many :enrollments, FunSheep.Courses.CourseEnrollment

    timestamps(type: :utc_datetime)
  end

  @access_levels ~w(public preview standard premium professional)

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
      :custom_textbook_name,
      :external_provider,
      :external_id,
      :external_synced_at,
      :ocr_started_at,
      :pending_toc_id,
      :pending_toc_proposed_by_id,
      :pending_toc_proposed_at,
      :access_level,
      :is_premium_catalog,
      :catalog_test_type,
      :catalog_subject,
      :catalog_level,
      :published_at,
      :published_by_id,
      :sample_question_count,
      :quality_score,
      :like_count,
      :dislike_count,
      :completion_count,
      :attempt_count,
      :unique_user_count,
      :quality_last_computed_at,
      :visibility_state,
      :dormant_at
    ])
    |> validate_required([:name, :subject, :grade])
    |> validate_inclusion(:access_level, @access_levels)
    |> validate_number(:sample_question_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:school_id)
    |> foreign_key_constraint(:pending_toc_id)
    |> foreign_key_constraint(:pending_toc_proposed_by_id)
    |> foreign_key_constraint(:published_by_id)
  end

  @doc """
  Changeset for updating premium catalog metadata.

  Validates catalog-specific fields required when marking a course as a
  premium catalog entry. `is_premium_catalog`, `catalog_test_type`, and
  `access_level` are required when the course is being published to the
  premium catalog.
  """
  def changeset_for_premium(course, attrs) do
    course
    |> changeset(attrs)
    |> validate_required([:catalog_test_type, :access_level])
    |> validate_inclusion(:access_level, @access_levels -- ["public"])
    |> validate_number(:sample_question_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 500
    )
  end
end
