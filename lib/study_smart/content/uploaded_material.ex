defmodule StudySmart.Content.UploadedMaterial do
  @moduledoc """
  Schema for uploaded course materials (PDFs, images, notes).

  Tracks the OCR processing status and links to the uploading user and course.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "uploaded_materials" do
    field :file_path, :string
    field :file_name, :string
    field :file_type, :string
    field :file_size, :integer

    field :ocr_status, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed],
      default: :pending

    belongs_to :user_role, StudySmart.Accounts.UserRole
    belongs_to :course, StudySmart.Courses.Course

    has_many :ocr_pages, StudySmart.Content.OcrPage, foreign_key: :material_id

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
      :ocr_status,
      :user_role_id,
      :course_id
    ])
    |> validate_required([
      :file_path,
      :file_name,
      :file_type,
      :file_size,
      :user_role_id,
      :course_id
    ])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end
end
