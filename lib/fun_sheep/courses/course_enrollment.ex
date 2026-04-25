defmodule FunSheep.Courses.CourseEnrollment do
  @moduledoc """
  Schema for course enrollments.

  Tracks which users have access to which courses, and how that access
  was granted (subscription, à la carte purchase, free, or gifted).

  `access_expires_at` being nil means permanent access.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @access_types ~w(subscription alacarte free gifted)

  schema "course_enrollments" do
    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    field :access_type, :string
    field :access_granted_at, :utc_datetime
    # nil = permanent access
    field :access_expires_at, :utc_datetime
    field :purchase_reference, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [
      :user_role_id,
      :course_id,
      :access_type,
      :access_granted_at,
      :access_expires_at,
      :purchase_reference
    ])
    |> validate_required([:user_role_id, :course_id, :access_type, :access_granted_at])
    |> validate_inclusion(:access_type, @access_types)
    |> unique_constraint([:user_role_id, :course_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end

  @doc "Returns the list of valid access types."
  def access_types, do: @access_types
end
