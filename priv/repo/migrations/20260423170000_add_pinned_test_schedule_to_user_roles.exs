defmodule FunSheep.Repo.Migrations.AddPinnedTestScheduleToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :pinned_test_schedule_id,
          references(:test_schedules, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:user_roles, [:pinned_test_schedule_id])
  end
end
