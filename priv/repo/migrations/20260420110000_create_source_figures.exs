defmodule FunSheep.Repo.Migrations.CreateSourceFigures do
  use Ecto.Migration

  def change do
    create table(:source_figures, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :ocr_page_id, references(:ocr_pages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :material_id,
          references(:uploaded_materials, type: :binary_id, on_delete: :delete_all),
          null: false

      add :page_number, :integer, null: false
      add :figure_number, :string
      add :figure_type, :string, null: false
      add :caption, :text
      add :image_path, :string, null: false
      add :bbox, :map
      add :width, :integer
      add :height, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:source_figures, [:ocr_page_id])
    create index(:source_figures, [:material_id])
    create index(:source_figures, [:material_id, :page_number])

    create table(:question_figures, primary_key: false) do
      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_figure_id, references(:source_figures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:question_figures, [:question_id, :source_figure_id])
    create index(:question_figures, [:source_figure_id])
  end
end
