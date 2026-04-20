defmodule FunSheep.Content.SourceFigure do
  @moduledoc """
  Schema for figures, tables, graphs, diagrams, and images extracted from
  source materials during OCR processing.

  Each figure stores a cropped image (via `image_path` in the storage backend)
  plus metadata derived from the Vision API bounding boxes and nearby captions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @figure_types [:figure, :table, :graph, :chart, :diagram, :image]

  def figure_types, do: @figure_types

  schema "source_figures" do
    field :page_number, :integer
    field :figure_number, :string
    field :figure_type, Ecto.Enum, values: @figure_types, default: :figure
    field :caption, :string
    field :image_path, :string
    field :bbox, :map
    field :width, :integer
    field :height, :integer

    belongs_to :ocr_page, FunSheep.Content.OcrPage
    belongs_to :material, FunSheep.Content.UploadedMaterial

    many_to_many :questions, FunSheep.Questions.Question,
      join_through: FunSheep.Questions.QuestionFigure,
      join_keys: [source_figure_id: :id, question_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(figure, attrs) do
    figure
    |> cast(attrs, [
      :page_number,
      :figure_number,
      :figure_type,
      :caption,
      :image_path,
      :bbox,
      :width,
      :height,
      :ocr_page_id,
      :material_id
    ])
    |> validate_required([:page_number, :figure_type, :image_path, :ocr_page_id, :material_id])
    |> validate_number(:page_number, greater_than: 0)
    |> foreign_key_constraint(:ocr_page_id)
    |> foreign_key_constraint(:material_id)
  end
end
