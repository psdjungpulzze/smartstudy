defmodule FunSheep.Social.CourseShareRecipient do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_share_recipients" do
    field :seen_at, :utc_datetime

    belongs_to :share, FunSheep.Social.CourseShare
    belongs_to :recipient, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(recipient, attrs) do
    recipient
    |> cast(attrs, [:share_id, :recipient_id, :seen_at])
    |> validate_required([:share_id, :recipient_id])
    |> unique_constraint([:share_id, :recipient_id])
  end

  def seen_changeset(recipient) do
    recipient |> change(seen_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end
