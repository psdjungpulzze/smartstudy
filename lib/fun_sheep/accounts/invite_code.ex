defmodule FunSheep.Accounts.InviteCode do
  @moduledoc """
  A single-use invite code a guardian hands to a not-yet-signed-up child
  so the child can link back to the guardian on signup.

  Used by Flow B's `/onboarding/parent` wizard (§5.2):

    * Parent enters child name (and optional email) in the wizard.
    * System creates an `invite_code` (14-day TTL) with the child's
      display name + optional email. If email is present, a pending
      email invite is also fired via `Accounts.invite_guardian/3`.
    * Child (either received email or was handed the code by parent)
      visits `/claim/:code`, authenticates via Interactor, redeems the
      code → system creates a `:active` `student_guardian` row between
      the guardian and the now-signed-up child.

  Single-use and expires after 14 days (§5.2). Codes are 8 chars of
  uppercase base32 (no ambiguous characters) for easy spoken hand-off.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @relationship_types ~w(parent teacher)a
  @ttl_days 14
  @code_length 8

  # Omit ambiguous characters (0/O, 1/I, etc.) for easy verbal sharing.
  @alphabet ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

  schema "invite_codes" do
    field :code, :string
    field :relationship_type, Ecto.Enum, values: @relationship_types
    field :child_display_name, :string
    field :child_grade, :string
    field :child_email, :string

    field :redeemed_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :guardian, FunSheep.Accounts.UserRole
    belongs_to :redeemed_by_user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new invite code. Auto-generates the code and
  stamps expiry unless overridden.
  """
  def create_changeset(invite, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires = DateTime.add(now, @ttl_days, :day)

    invite
    |> cast(attrs, [
      :guardian_id,
      :relationship_type,
      :child_display_name,
      :child_grade,
      :child_email,
      :metadata
    ])
    |> put_change(:code, generate_code())
    |> put_change(:expires_at, expires)
    |> validate_required([:guardian_id, :relationship_type, :child_display_name])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> maybe_validate_email()
    |> foreign_key_constraint(:guardian_id)
    |> unique_constraint(:code)
  end

  @doc "Changeset for stamping the redemption."
  def redeem_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:redeemed_at, :redeemed_by_user_role_id])
    |> validate_required([:redeemed_at, :redeemed_by_user_role_id])
    |> foreign_key_constraint(:redeemed_by_user_role_id)
  end

  @doc "Returns true when the code has not been redeemed and is not expired."
  def active?(%__MODULE__{redeemed_at: nil, expires_at: %DateTime{} = expires}) do
    DateTime.compare(DateTime.utc_now(), expires) == :lt
  end

  def active?(_), do: false

  @doc "Generates a random 8-char base32 code."
  def generate_code do
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(@alphabet) end)
    |> List.to_string()
  end

  def ttl_days, do: @ttl_days

  defp maybe_validate_email(changeset) do
    case get_change(changeset, :child_email) do
      nil -> changeset
      "" -> changeset
      _ -> validate_format(changeset, :child_email, ~r/^[^\s]+@[^\s]+$/)
    end
  end
end
