defmodule FunSheep.Accounts.UserRoleTest do
  @moduledoc """
  Minimal test covering the `:timezone` field added for §9.3 quiet-hours.
  Full UserRole coverage lives in context tests.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Repo

  describe ":timezone field (§9.3)" do
    test "persists a valid IANA timezone string" do
      {:ok, role} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :parent,
          email: "tz_#{System.unique_integer([:positive])}@test.com",
          display_name: "TZ Parent",
          timezone: "America/Los_Angeles"
        })

      reloaded = Repo.get!(UserRole, role.id)
      assert reloaded.timezone == "America/Los_Angeles"
    end

    test "timezone is optional (defaults to nil)" do
      {:ok, role} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :parent,
          email: "tz2_#{System.unique_integer([:positive])}@test.com",
          display_name: "No TZ"
        })

      assert is_nil(role.timezone)
    end
  end
end
