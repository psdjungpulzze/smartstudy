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

  def material_kinds, do: @material_kinds

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

    field :relevance_status, :string, default: "pending"
    field :relevance_score, :float
    field :relevance_notes, :string

    field :completeness_score, :float
    field :completeness_notes, :string
    field :toc_detected, :boolean, default: false
    field :completeness_checked_at, :utc_datetime

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
      :relevance_status,
      :relevance_score,
      :relevance_notes,
      :completeness_score,
      :completeness_notes,
      :toc_detected,
      :completeness_checked_at,
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
