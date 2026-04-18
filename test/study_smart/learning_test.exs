defmodule StudySmart.LearningTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Learning
  alias StudySmart.Accounts

  describe "hobbies" do
    test "list_hobbies/0 returns all hobbies" do
      {:ok, hobby} =
        Learning.create_hobby(%{
          name: "Test Hobby",
          category: "Test Category",
          region_relevance: %{"US" => 0.8}
        })

      hobbies = Learning.list_hobbies()
      assert Enum.any?(hobbies, fn h -> h.id == hobby.id end)
    end

    test "create_hobby/1 creates a hobby with valid data" do
      attrs = %{
        name: "Drawing",
        category: "Art",
        region_relevance: %{"US" => 0.7, "KR" => 0.6}
      }

      assert {:ok, hobby} = Learning.create_hobby(attrs)
      assert hobby.name == "Drawing"
      assert hobby.category == "Art"
      assert hobby.region_relevance == %{"US" => 0.7, "KR" => 0.6}
    end

    test "create_hobby/1 fails without required fields" do
      assert {:error, changeset} = Learning.create_hobby(%{})
      assert %{name: _, category: _} = errors_on(changeset)
    end
  end

  describe "student_hobbies" do
    setup do
      {:ok, user_role} =
        Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :student,
          email: "student_#{System.unique_integer([:positive])}@test.com"
        })

      {:ok, hobby} =
        Learning.create_hobby(%{
          name: "Hobby #{System.unique_integer([:positive])}",
          category: "Test"
        })

      %{user_role: user_role, hobby: hobby}
    end

    test "create_student_hobby/1 creates an association", %{
      user_role: user_role,
      hobby: hobby
    } do
      attrs = %{
        user_role_id: user_role.id,
        hobby_id: hobby.id,
        specific_interests: %{"favorites" => "BTS, BlackPink"}
      }

      assert {:ok, student_hobby} = Learning.create_student_hobby(attrs)
      assert student_hobby.user_role_id == user_role.id
      assert student_hobby.hobby_id == hobby.id
    end

    test "list_hobbies_for_user/1 returns hobbies for a specific user", %{
      user_role: user_role,
      hobby: hobby
    } do
      {:ok, _sh} =
        Learning.create_student_hobby(%{
          user_role_id: user_role.id,
          hobby_id: hobby.id
        })

      student_hobbies = Learning.list_hobbies_for_user(user_role.id)
      assert length(student_hobbies) == 1
      assert hd(student_hobbies).hobby.id == hobby.id
    end

    test "enforces unique user_role + hobby constraint", %{
      user_role: user_role,
      hobby: hobby
    } do
      {:ok, _sh} =
        Learning.create_student_hobby(%{
          user_role_id: user_role.id,
          hobby_id: hobby.id
        })

      assert {:error, changeset} =
               Learning.create_student_hobby(%{
                 user_role_id: user_role.id,
                 hobby_id: hobby.id
               })

      assert %{user_role_id: _} = errors_on(changeset)
    end
  end
end
