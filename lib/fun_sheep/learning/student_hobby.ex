defmodule FunSheep.Learning.StudentHobby do
  @moduledoc """
  Schema for the join between students (user roles) and hobbies.

  Stores specific interests within each hobby for deeper personalization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "student_hobbies" do
    field :specific_interests, :map

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :hobby, FunSheep.Learning.Hobby

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(student_hobby, attrs) do
    student_hobby
    |> cast(attrs, [:specific_interests, :user_role_id, :hobby_id])
    |> validate_required([:user_role_id, :hobby_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:hobby_id)
    |> unique_constraint([:user_role_id, :hobby_id])
  end
end
