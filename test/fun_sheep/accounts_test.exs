defmodule FunSheep.AccountsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts

  describe "create_user_role/1" do
    test "creates a user role with valid data" do
      attrs = %{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "student@test.com",
        display_name: "Test Student"
      }

      assert {:ok, user_role} = Accounts.create_user_role(attrs)
      assert user_role.role == :student
      assert user_role.email == "student@test.com"
      assert user_role.display_name == "Test Student"
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = Accounts.create_user_role(%{})
      assert %{interactor_user_id: _, role: _, email: _} = errors_on(changeset)
    end

    test "returns error with invalid email format" do
      attrs = %{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "not-an-email"
      }

      assert {:error, changeset} = Accounts.create_user_role(attrs)
      assert %{email: _} = errors_on(changeset)
    end

    test "validates role enum values" do
      attrs = %{
        interactor_user_id: Ecto.UUID.generate(),
        role: :student,
        email: "student@test.com"
      }

      assert {:ok, _} = Accounts.create_user_role(attrs)

      parent_attrs = %{
        attrs
        | interactor_user_id: Ecto.UUID.generate(),
          role: :parent,
          email: "parent@test.com"
      }

      assert {:ok, _} = Accounts.create_user_role(parent_attrs)

      teacher_attrs = %{
        attrs
        | interactor_user_id: Ecto.UUID.generate(),
          role: :teacher,
          email: "teacher@test.com"
      }

      assert {:ok, _} = Accounts.create_user_role(teacher_attrs)
    end

    test "rejects invalid role" do
      attrs = %{
        interactor_user_id: Ecto.UUID.generate(),
        role: :invalid_role,
        email: "test@test.com"
      }

      assert {:error, changeset} = Accounts.create_user_role(attrs)
      assert %{role: _} = errors_on(changeset)
    end

    test "enforces unique interactor_user_id" do
      interactor_id = Ecto.UUID.generate()

      attrs = %{
        interactor_user_id: interactor_id,
        role: :student,
        email: "first@test.com"
      }

      assert {:ok, _} = Accounts.create_user_role(attrs)

      duplicate_attrs = %{
        interactor_user_id: interactor_id,
        role: :parent,
        email: "second@test.com"
      }

      assert {:error, changeset} = Accounts.create_user_role(duplicate_attrs)
      assert %{interactor_user_id: _} = errors_on(changeset)
    end
  end
end
