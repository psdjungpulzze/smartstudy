defmodule FunSheep.Repo.Migrations.AddOnboardingCompletedAtToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      add :onboarding_completed_at, :utc_datetime, null: true
    end
  end
end
