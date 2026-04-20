defmodule FunSheep.Content.OcrPage do
  @moduledoc """
  Schema for OCR-processed pages from uploaded materials.

  Stores extracted text, bounding box metadata, and image references per page.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ocr_pages" do
    field :page_number, :integer
    field :extracted_text, :string
    field :bounding_boxes, :map
    field :images, :map

    field :status, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed],
      default: :completed

    field :error, :string

    belongs_to :material, FunSheep.Content.UploadedMaterial
    has_many :figures, FunSheep.Content.SourceFigure

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ocr_page, attrs) do
    ocr_page
    |> cast(attrs, [
      :page_number,
      :extracted_text,
      :bounding_boxes,
      :images,
      :status,
      :error,
      :material_id
    ])
    |> validate_required([:page_number, :material_id])
    |> validate_number(:page_number, greater_than: 0)
    |> foreign_key_constraint(:material_id)
    |> unique_constraint([:material_id, :page_number])
  end
end
