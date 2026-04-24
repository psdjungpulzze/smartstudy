defmodule FunSheep.Repo.Migrations.CreateSectionOverviews do
  use Ecto.Migration

  def change do
    create table(:section_overviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :section_id, references(:sections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :body, :text, null: false
      add :generated_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_overviews, [:section_id, :user_role_id])
    create index(:section_overviews, [:section_id])
  end
end
