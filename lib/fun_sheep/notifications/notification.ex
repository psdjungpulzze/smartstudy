defmodule FunSheep.Notifications.Notification do
  @moduledoc """
  Schema representing a single notification sent (or to be sent) to a user.

  One row per channel per notification event. A single streak alert for a
  student generates one :in_app row and, if push is enabled, one :push row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(
    streak_at_risk
    streak_milestone
    test_upcoming_3d
    test_upcoming_1d
    readiness_drop
    readiness_milestone
    skill_mastered
    skill_weak_confirmed
    invite_received
    share_received
    friend_milestone
    friend_joined
    inactivity
    weekly_digest
    class_digest
    student_at_risk
    daily_habit_nudge
  )a

  @channels ~w(push email in_app sms)a

  @statuses ~w(pending sent failed read dismissed)a

  schema "notifications" do
    field :type, Ecto.Enum, values: @types
    field :channel, Ecto.Enum, values: @channels
    # 0 = critical (always send), 1 = high, 2 = medium (default), 3 = low
    field :priority, :integer, default: 2
    field :title, :string
    field :body, :string
    field :payload, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :scheduled_for, :utc_datetime
    field :sent_at, :utc_datetime
    field :read_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole

    # inserted_at only — no updated_at (immutable after creation)
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required ~w(user_role_id type channel body scheduled_for)a
  @optional ~w(priority title payload status sent_at read_at)a

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:priority, 0..3)
    |> validate_length(:body, max: 500)
    |> validate_length(:title, max: 200)
    |> foreign_key_constraint(:user_role_id)
  end

  def types, do: @types
  def channels, do: @channels
end
