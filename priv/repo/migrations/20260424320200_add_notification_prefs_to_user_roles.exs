defmodule FunSheep.Repo.Migrations.AddNotificationPrefsToUserRoles do
  use Ecto.Migration

  def change do
    alter table(:user_roles) do
      # Master push toggle — false = no push of any kind.
      add_if_not_exists :push_enabled, :boolean, null: false, default: true

      # Frequency cap tier: off / light (1-2/wk) / standard (3-5/wk) / all (no cap).
      add_if_not_exists :notification_frequency, :string, null: false, default: "standard"

      # Quiet hours (local-hour integers). Default: 21:00–08:00.
      add_if_not_exists :notification_quiet_start, :integer, null: false, default: 21
      add_if_not_exists :notification_quiet_end, :integer, null: false, default: 8

      # Per-alert-type opt-outs (student-specific).
      add_if_not_exists :alerts_streak, :boolean, null: false, default: true
      add_if_not_exists :alerts_friend_activity, :boolean, null: false, default: true
      add_if_not_exists :alerts_test_upcoming, :boolean, null: false, default: true

      # Per-alert-type opt-outs (teacher-specific).
      add_if_not_exists :alerts_student_at_risk, :boolean, null: false, default: true
      add_if_not_exists :alerts_class_digest, :boolean, null: false, default: true
    end
  end
end
