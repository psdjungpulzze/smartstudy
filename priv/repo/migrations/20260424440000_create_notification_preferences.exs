defmodule FunSheep.Repo.Migrations.CreateNotificationPreferences do
  use Ecto.Migration

  @doc """
  Per-user, per-channel, (optionally) per-type notification preferences.

  One row covers the channel-level default (notification_type IS NULL).
  An additional row overrides a specific type within that channel.

  Example: a student silences all push, but keeps streak-at-risk push on:
    (user_role_id, :push, nil,             enabled: false)  -- default off
    (user_role_id, :push, :streak_at_risk, enabled: true)   -- override on
  """
  def change do
    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      # "push" | "email" | "in_app" | "sms"
      add :channel, :string, null: false

      # NULL = applies to all notification types on this channel.
      # Non-null = type-specific override (e.g. "streak_at_risk").
      add :notification_type, :string

      # Whether this channel/type combination is enabled for the user.
      add :enabled, :boolean, null: false, default: true

      # Local-hour integer (0-23). Quiet window: do not send during [quiet_start, quiet_end).
      # Overrides the user_roles.notification_quiet_start / quiet_end at channel level.
      add :quiet_start, :integer
      add :quiet_end, :integer

      # "off" | "light" | "standard" | "all" — frequency tier for this channel.
      add :frequency_tier, :string, null: false, default: "standard"

      # Optional preferred delivery time (local hour). E.g. prefer email at 08:00.
      add :preferred_hour, :integer

      add :updated_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    # Enforce one preference row per (user, channel, type) combination.
    # Two indexes are needed because PostgreSQL treats NULL != NULL in a standard
    # unique index, which would allow multiple channel-default rows (type IS NULL).
    create unique_index(:notification_preferences, [:user_role_id, :channel, :notification_type],
             name: :notification_preferences_user_channel_type_index,
             where: "notification_type IS NOT NULL"
           )

    # Separate partial unique index for the channel-default rows (type IS NULL).
    create unique_index(:notification_preferences, [:user_role_id, :channel],
             name: :notification_preferences_user_channel_null_type_index,
             where: "notification_type IS NULL"
           )

    create index(:notification_preferences, [:user_role_id])
  end
end
