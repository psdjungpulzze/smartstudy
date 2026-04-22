defmodule FunSheep.Repo.Migrations.AddNotificationPrefsToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      # :weekly | :off — per spec §8.1 digest_frequency preference.
      add :digest_frequency, :string, default: "weekly"

      # Opt-in alert flags — default false except goal_achieved (true), per §8.2.
      add :alerts_skipped_days, :boolean, default: false, null: false
      add :alerts_readiness_drop, :boolean, default: false, null: false
      add :alerts_goal_achieved, :boolean, default: true, null: false
    end
  end
end
