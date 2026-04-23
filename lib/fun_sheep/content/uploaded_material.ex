defmodule FunSheep.Content.UploadedMaterial do
  @moduledoc """
  Schema for uploaded course materials (PDFs, images, notes).

  Tracks the OCR processing status and links to the uploading user and course.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @material_kinds [
    :textbook,
    :supplementary_book,
    :sample_questions,
    :lecture_notes,
    :syllabus,
    :other
  ]

  # Phase 2 classifier output — superset of `@material_kinds` because the
  # classifier can detect categories users can't or won't label.
  # `:answer_key` is the load-bearing addition: an answer-key image
  # mislabeled as `:textbook` produced 462 garbage questions in the
  # mid-April prod audit.
  @classified_kinds [
    :question_bank,
    :answer_key,
    :knowledge_content,
    :mixed,
    :unusable,
    :uncertain
  ]

  def material_kinds, do: @material_kinds
  def classified_kinds, do: @classified_kinds

  schema "uploaded_materials" do
    field :file_path, :string
    field :file_name, :string
    field :file_type, :string
    field :file_size, :integer
    field :folder_name, :string
    field :batch_id, Ecto.UUID

    field :material_kind, Ecto.Enum,
      values: @material_kinds,
      default: :textbook

    field :ocr_status, Ecto.Enum,
      values: [:pending, :processing, :completed, :partial, :failed],
      default: :pending

    field :ocr_error, :string

    # Async PDF OCR tracking. One material splits into N chunks; each chunk
    # becomes one Vision `files:asyncBatchAnnotate` long-running operation.
    # Shape: %{"chunks" => [%{"name" => "operations/...", "start_page" => 1,
    #                          "page_count" => 200, "output_prefix" => "...",
    #                          "status" => "running" | "done" | "failed",
    #                          "error" => nil | String.t()}]}
    field :ocr_operations, :map, default: %{}

    # Set by the dispatch worker once the PDF is page-counted. OcrPage rows
    # are upserted into ocr_pages; the chunk pollers atomically
    # increment :ocr_pages_completed so the parent can decide when all
    # chunks have finished without scanning the full array.
    field :ocr_pages_expected, :integer
    field :ocr_pages_completed, :integer, default: 0

    field :relevance_status, :string, default: "pending"
    field :relevance_score, :float
    field :relevance_notes, :string

    field :completeness_score, :float
    field :completeness_notes, :string
    field :toc_detected, :boolean, default: false
    field :completeness_checked_at, :utc_datetime

    # Phase 2 AI classification. Separate from user-supplied
    # `material_kind` so intent is preserved and admin can reconcile
    # mismatches. Routing logic (extractor vs grounding vs skip) trusts
    # `classified_kind` when confidence is high, falls back to
    # `material_kind` when confidence is low or classification hasn't
    # run yet.
    field :classified_kind, Ecto.Enum, values: @classified_kinds
    field :kind_confidence, :float
    field :kind_classified_at, :utc_datetime
    field :kind_classification_notes, :string

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    has_many :ocr_pages, FunSheep.Content.OcrPage, foreign_key: :material_id
    has_many :figures, FunSheep.Content.SourceFigure, foreign_key: :material_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(uploaded_material, attrs) do
    uploaded_material
    |> cast(attrs, [
      :file_path,
      :file_name,
      :file_type,
      :file_size,
      :folder_name,
      :batch_id,
      :material_kind,
      :ocr_status,
      :ocr_error,
      :ocr_operations,
      :ocr_pages_expected,
      :ocr_pages_completed,
      :relevance_status,
      :relevance_score,
      :relevance_notes,
      :completeness_score,
      :completeness_notes,
      :toc_detected,
      :completeness_checked_at,
      :classified_kind,
      :kind_confidence,
      :kind_classified_at,
      :kind_classification_notes,
      :user_role_id,
      :course_id
    ])
    |> validate_required([
      :file_path,
      :file_name,
      :file_type,
      :file_size,
      :user_role_id
    ])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end
end
