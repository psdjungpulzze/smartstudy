defmodule StudySmart.Repo.Migrations.CreateMaterialsAndOcr do
  use Ecto.Migration

  def change do
    create_query =
      "CREATE TYPE ocr_status AS ENUM ('pending', 'processing', 'completed', 'failed')"

    drop_query = "DROP TYPE IF EXISTS ocr_status"
    execute(create_query, drop_query)

    create_if_not_exists table(:uploaded_materials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :file_name, :string, null: false
      add :file_path, :string, null: false
      add :file_type, :string, null: false
      add :file_size, :integer, null: false
      add :ocr_status, :ocr_status, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:uploaded_materials, [:user_role_id])
    create_if_not_exists index(:uploaded_materials, [:course_id])
    create_if_not_exists index(:uploaded_materials, [:ocr_status])

    create_if_not_exists table(:ocr_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :material_id, references(:uploaded_materials, type: :binary_id, on_delete: :delete_all),
        null: false

      add :page_number, :integer, null: false
      add :extracted_text, :text
      add :bounding_boxes, :map
      add :images, :map

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:ocr_pages, [:material_id])
    create_if_not_exists index(:ocr_pages, [:material_id, :page_number])
  end
end
