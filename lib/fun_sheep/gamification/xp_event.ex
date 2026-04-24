defmodule FunSheep.Gamification.XpEvent do
  @moduledoc """
  Schema for XP (Fleece Points) events.

  Records every XP-earning action for audit trail and total calculation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_sources ~w(assessment practice quick_test streak_bonus daily_challenge study_guide achievement review study_session study_buddy)

  schema "xp_events" do
    field :amount, :integer
    field :source, :string
    field :source_id, :binary_id
    field :metadata, :map, default: %{}

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(xp_event, attrs) do
    xp_event
    |> cast(attrs, [:amount, :source, :source_id, :metadata, :user_role_id])
    |> validate_required([:amount, :source, :user_role_id])
    |> validate_inclusion(:source, @valid_sources)
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:user_role_id)
  end
end
