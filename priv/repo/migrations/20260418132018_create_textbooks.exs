defmodule FunSheep.Repo.Migrations.CreateTextbooks do
  use Ecto.Migration

  def change do
    create table(:textbooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :author, :string
      add :publisher, :string
      add :edition, :string
      add :isbn, :string
      add :cover_image_url, :string
      add :subject, :string, null: false
      add :grades, {:array, :string}, default: []
      add :openlibrary_key, :string

      timestamps(type: :utc_datetime)
    end

    create index(:textbooks, [:subject])
    create unique_index(:textbooks, [:isbn], where: "isbn IS NOT NULL")
    create unique_index(:textbooks, [:openlibrary_key], where: "openlibrary_key IS NOT NULL")

    alter table(:courses) do
      add :textbook_id, references(:textbooks, type: :binary_id, on_delete: :nilify_all)
      add :custom_textbook_name, :string
    end

    create index(:courses, [:textbook_id])
  end
end
