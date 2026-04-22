defmodule FunSheep.Courses.TOCAcknowledgement do
  @moduledoc """
  Records that a given user has dismissed the "course structure was updated"
  banner for a specific applied TOC. Used to show the banner exactly once per
  user per TOC change — the next rebase (a new DiscoveredTOC) shows the
  banner fresh.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_course_toc_acknowledgements" do
    field :dismissed_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :discovered_toc, FunSheep.Courses.DiscoveredTOC

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ack, attrs) do
    ack
    |> cast(attrs, [:user_role_id, :course_id, :discovered_toc_id, :dismissed_at])
    |> validate_required([:user_role_id, :course_id, :discovered_toc_id, :dismissed_at])
    |> unique_constraint([:user_role_id, :discovered_toc_id],
      name: :user_course_toc_acks_unique
    )
  end
end
