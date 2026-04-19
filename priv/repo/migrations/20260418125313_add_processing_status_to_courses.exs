defmodule FunSheep.Repo.Migrations.AddProcessingStatusToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :processing_status, :string, default: "pending"
      add :processing_step, :string
      add :processing_error, :text
      add :ocr_completed_count, :integer, default: 0
      add :ocr_total_count, :integer, default: 0
    end
  end
end
