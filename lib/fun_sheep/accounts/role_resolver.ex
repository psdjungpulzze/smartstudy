defmodule FunSheep.Accounts.RoleResolver do
  @moduledoc """
  Resolves the effective role for a user logging in.

  The inputs come from two sources with different trust levels:

    * `claim_role` — the `metadata.role` value fetched server-to-server from
      Interactor. **Trusted.**
    * `selected_role` — a role string provided in the request (query param or
      form field). **Untrusted** — user-controllable.

  The rule: admin status can only come from the trusted claim. A user-supplied
  role may switch between the safe roles (student/parent/teacher) but cannot
  elevate to admin.

  This module exists as a separate unit so the privilege boundary can be
  tested directly without mocking the entire login flow.
  """

  @safe_roles ~w(student parent teacher)
  @all_roles ["admin" | @safe_roles]

  @doc """
  Returns the effective role string.

  Admin claim wins unconditionally. Otherwise the selected role wins if it is
  a safe role; otherwise the claim; otherwise `"student"`.
  """
  @spec resolve(String.t() | nil, String.t() | nil) :: String.t()
  def resolve("admin", _selected), do: "admin"

  def resolve(claim_role, selected_role) do
    case selected_role do
      role when role in @safe_roles -> role
      _ -> normalize(claim_role) || "student"
    end
  end

  @doc """
  Validates a role string, returning it when recognised or `nil` otherwise.
  """
  @spec normalize(term()) :: String.t() | nil
  def normalize(role) when role in @all_roles, do: role
  def normalize(_), do: nil

  @doc "Returns the list of roles a user may select for themselves."
  def safe_roles, do: @safe_roles
end
