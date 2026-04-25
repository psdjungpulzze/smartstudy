defmodule FunSheep.Social.Follow do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active muted blocked)
  @sources ~w(manual suggested_school suggested_course suggested_fof invite_accepted course_shared)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "social_follows" do
    field :status, :string, default: "active"
    field :source, :string, default: "manual"

    belongs_to :follower, FunSheep.Accounts.UserRole
    belongs_to :following, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:follower_id, :following_id, :status, :source])
    |> validate_required([:follower_id, :following_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:follower_id, :following_id])
    |> check_constraint(:follower_id, name: :no_self_follow)
  end

  def status_changeset(follow, attrs) do
    follow
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
