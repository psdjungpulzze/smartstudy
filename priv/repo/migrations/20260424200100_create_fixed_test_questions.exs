defmodule FunSheep.Repo.Migrations.CreateFixedTestQuestions do
  use Ecto.Migration

  def change do
    create table(:fixed_test_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bank_id, references(:fixed_test_banks, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false
      add :question_text, :text, null: false
      add :answer_text, :text, null: false
      add :question_type, :string, null: false, default: "multiple_choice"
      add :options, :jsonb
      add :explanation, :text
      add :points, :integer, null: false, default: 1
      add :image_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_test_questions, [:bank_id])
    create index(:fixed_test_questions, [:bank_id, :position])
  end
end
