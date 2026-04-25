defmodule FunSheep.Repo.Migrations.AddOcrStartedAtToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :ocr_started_at, :utc_datetime, null: true
    end
  end
end
