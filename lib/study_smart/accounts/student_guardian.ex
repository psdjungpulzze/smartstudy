defmodule StudySmart.Accounts.StudentGuardian do
  @moduledoc """
  Schema for guardian (parent/teacher) to student relationships.

  Tracks the invite/accept lifecycle for linking guardians to students.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "student_guardians" do
    field :relationship_type, Ecto.Enum, values: [:parent, :teacher]
    field :status, Ecto.Enum, values: [:pending, :active, :revoked]
    field :class_name, :string
    field :invited_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :guardian, StudySmart.Accounts.UserRole
    belongs_to :student, StudySmart.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(student_guardian, attrs) do
    student_guardian
    |> cast(attrs, [
      :relationship_type,
      :status,
      :class_name,
      :invited_at,
      :accepted_at,
      :guardian_id,
      :student_id
    ])
    |> validate_required([:relationship_type, :status, :guardian_id, :student_id])
    |> foreign_key_constraint(:guardian_id)
    |> foreign_key_constraint(:student_id)
    |> unique_constraint([:guardian_id, :student_id])
  end
end
