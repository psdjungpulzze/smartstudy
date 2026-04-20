defmodule FunSheep.Tutorials.UserTutorial do
  @moduledoc """
  Tracks which in-app tutorials a user has seen.

  One row per (user_role_id, tutorial_key). Presence means the user has
  completed/dismissed that tutorial at least once.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_tutorials" do
    field :tutorial_key, :string
    field :completed_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tutorial, attrs) do
    tutorial
    |> cast(attrs, [:user_role_id, :tutorial_key, :completed_at])
    |> validate_required([:user_role_id, :tutorial_key, :completed_at])
    |> unique_constraint([:user_role_id, :tutorial_key])
    |> foreign_key_constraint(:user_role_id)
  end
end
