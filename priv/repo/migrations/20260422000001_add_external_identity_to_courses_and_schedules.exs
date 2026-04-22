defmodule FunSheep.Repo.Migrations.AddExternalIdentityToCoursesAndSchedules do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :external_provider, :string
      add :external_id, :string
      add :external_synced_at, :utc_datetime
    end

    create unique_index(
             :courses,
             [:created_by_id, :external_provider, :external_id],
             where: "external_provider IS NOT NULL",
             name: :courses_external_identity_index
           )

    alter table(:test_schedules) do
      add :external_provider, :string
      add :external_id, :string
      add :external_synced_at, :utc_datetime
    end

    create unique_index(
             :test_schedules,
             [:user_role_id, :external_provider, :external_id],
             where: "external_provider IS NOT NULL",
             name: :test_schedules_external_identity_index
           )
  end
end
