defmodule FunSheep.Repo.Migrations.AddQuestionValidationFields do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :validation_status, :string, default: "pending", null: false
      add :validation_score, :float
      add :validation_report, :map, default: %{}
      add :validated_at, :utc_datetime
      add :explanation, :text
    end

    create index(:questions, [:validation_status])
    create index(:questions, [:course_id, :validation_status])
  end
end
