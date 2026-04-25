defmodule FunSheep.Repo.Migrations.AddGroupFieldsToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :question_group_id,
          references(:question_groups, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :group_sequence, :integer, null: true
    end

    create index(:questions, [:question_group_id])
    create index(:questions, [:question_group_id, :group_sequence])
  end
end
