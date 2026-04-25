defmodule FunSheep.Repo.Migrations.CreateVideoResources do
  use Ecto.Migration

  def change do
    create table(:video_resources, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :section_id, references(:sections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false

      add :title, :string, null: false, size: 255
      add :url, :text, null: false
      # 'youtube', 'khan_academy', 'other'
      add :source, :string, null: false
      add :thumbnail_url, :text
      add :duration_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:video_resources, [:section_id])
    create index(:video_resources, [:course_id])
  end
end
