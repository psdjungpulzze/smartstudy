defmodule FunSheep.Accounts.StudentGuardian do
  @moduledoc """
  Schema for guardian (parent/teacher) to student relationships.

  Tracks the invite/accept lifecycle for linking guardians to students.

  Two shapes of pending invites are supported:

    * **Account-resolved** — `guardian_id` is set to an existing
      `UserRole` (parent/teacher). The guardian accepts on their next
      sign-in from the `/guardians` pending list.
    * **Email-only** — `guardian_id` is `nil` and `invited_email` holds
      the address the student entered. A secure `invite_token` (with
      `invite_token_expires_at` 14 days out) is emailed; the recipient
      signs in and visits `/guardian-invite/:token` to claim the link.
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

    field :invited_email, :string
    field :invite_token, :string
    field :invite_token_expires_at, :utc_datetime

    belongs_to :guardian, FunSheep.Accounts.UserRole
    belongs_to :student, FunSheep.Accounts.UserRole

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
      :student_id,
      :invited_email,
      :invite_token,
      :invite_token_expires_at
    ])
    |> validate_required([:relationship_type, :status, :student_id])
    |> validate_guardian_or_email()
    |> foreign_key_constraint(:guardian_id)
    |> foreign_key_constraint(:student_id)
    |> unique_constraint([:guardian_id, :student_id])
    |> unique_constraint(:invite_token, name: :student_guardians_invite_token_index)
  end

  defp validate_guardian_or_email(changeset) do
    guardian_id = get_field(changeset, :guardian_id)
    invited_email = get_field(changeset, :invited_email)

    if is_nil(guardian_id) and (is_nil(invited_email) or invited_email == "") do
      add_error(changeset, :guardian_id, "or invited_email must be present")
    else
      changeset
    end
  end
end
