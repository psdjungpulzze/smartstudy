defmodule FunSheep.Notifications.NotificationPreference do
  @moduledoc """
  Per-user, per-channel, (optionally) per-type notification preference.

  A NULL `notification_type` row acts as the channel-level default.
  A non-null `notification_type` row overrides the default for that specific
  notification type within the channel.

  Example: push defaults to disabled, but streak_at_risk is still delivered:
    {user_role_id, :push, nil,            enabled: false}  -- channel default
    {user_role_id, :push, :streak_at_risk, enabled: true}  -- type override

  Quiet-hour fields (`quiet_start` / `quiet_end`) override the user-level
  `notification_quiet_start` / `notification_quiet_end` stored on `user_roles`
  when present.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(push email in_app sms)a
  @frequency_tiers ~w(off light standard all)a

  schema "notification_preferences" do
    field :channel, Ecto.Enum, values: @channels
    field :notification_type, :string
    field :enabled, :boolean, default: true
    field :quiet_start, :integer
    field :quiet_end, :integer
    field :frequency_tier, Ecto.Enum, values: @frequency_tiers, default: :standard
    field :preferred_hour, :integer

    belongs_to :user_role, FunSheep.Accounts.UserRole

    # No inserted_at — only updated_at (preferences are upserted, not appended).
    field :updated_at, :utc_datetime
  end

  @required ~w(user_role_id channel enabled frequency_tier)a
  @optional ~w(notification_type quiet_start quiet_end preferred_hour)a

  @doc false
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:quiet_start, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:quiet_end, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:preferred_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> foreign_key_constraint(:user_role_id)
    |> unique_constraint([:user_role_id, :channel, :notification_type],
      name: :notification_preferences_user_channel_type_index
    )
    |> unique_constraint([:user_role_id, :channel],
      name: :notification_preferences_user_channel_null_type_index
    )
  end
end
