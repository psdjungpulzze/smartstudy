defmodule FunSheep.Repo.Migrations.AddParentExperienceIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:study_sessions, [:user_role_id, :completed_at])

    create_if_not_exists index(:question_attempts, [:user_role_id, :inserted_at])

    create_if_not_exists index(
                           :readiness_scores,
                           [:user_role_id, :test_schedule_id, :calculated_at]
                         )

    create_if_not_exists index(:student_guardians, [:guardian_id, :status])

    create_if_not_exists index(:student_guardians, [:student_id, :status])
  end
end
