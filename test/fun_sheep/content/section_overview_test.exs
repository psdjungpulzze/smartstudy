defmodule FunSheep.Content.SectionOverviewTest do
  @moduledoc """
  Tests for section overview CRUD operations in the Content context.
  """
  use FunSheep.DataCase, async: true

  alias FunSheep.Content
  alias FunSheep.Content.SectionOverview
  alias FunSheep.Courses
  alias FunSheep.Repo

  # ── Setup helpers ──

  defp create_user_role do
    {:ok, country} =
      %FunSheep.Geo.Country{}
      |> FunSheep.Geo.Country.changeset(%{
        name: "Test Country #{System.unique_integer([:positive])}",
        code: "TC#{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, state} =
      %FunSheep.Geo.State{}
      |> FunSheep.Geo.State.changeset(%{name: "Test State", country_id: country.id})
      |> Repo.insert()

    {:ok, district} =
      %FunSheep.Geo.District{}
      |> FunSheep.Geo.District.changeset(%{name: "Test District", state_id: state.id})
      |> Repo.insert()

    {:ok, school} =
      %FunSheep.Geo.School{}
      |> FunSheep.Geo.School.changeset(%{name: "Test School", district_id: district.id})
      |> Repo.insert()

    {:ok, user_role} =
      %FunSheep.Accounts.UserRole{}
      |> FunSheep.Accounts.UserRole.changeset(%{
        interactor_user_id: "user_#{System.unique_integer([:positive])}",
        role: :student,
        email: "test#{System.unique_integer([:positive])}@example.com",
        display_name: "Test User",
        school_id: school.id
      })
      |> Repo.insert()

    user_role
  end

  defp create_section do
    {:ok, course} = Courses.create_course(%{name: "Test Course", subject: "Biology", grade: "10"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Cell Division", position: 1, chapter_id: chapter.id})

    section
  end

  # ── Tests ──

  describe "get_section_overview/2" do
    test "returns nil when no overview exists" do
      user_role = create_user_role()
      section = create_section()

      assert is_nil(Content.get_section_overview(section.id, user_role.id))
    end

    test "returns the overview when it exists" do
      user_role = create_user_role()
      section = create_section()

      {:ok, _} = Content.upsert_section_overview(section.id, user_role.id, "Cell division is...")

      overview = Content.get_section_overview(section.id, user_role.id)
      assert %SectionOverview{} = overview
      assert overview.section_id == section.id
      assert overview.user_role_id == user_role.id
      assert overview.body == "Cell division is..."
    end

    test "does not return another user's overview" do
      user_role1 = create_user_role()
      user_role2 = create_user_role()
      section = create_section()

      {:ok, _} =
        Content.upsert_section_overview(section.id, user_role1.id, "User1's overview")

      assert is_nil(Content.get_section_overview(section.id, user_role2.id))
    end
  end

  describe "upsert_section_overview/3" do
    test "inserts a new overview when none exists" do
      user_role = create_user_role()
      section = create_section()

      assert {:ok, %SectionOverview{} = overview} =
               Content.upsert_section_overview(section.id, user_role.id, "Mitosis overview.")

      assert overview.body == "Mitosis overview."
      assert overview.section_id == section.id
      assert overview.user_role_id == user_role.id
      refute is_nil(overview.generated_at)
    end

    test "updates an existing overview" do
      user_role = create_user_role()
      section = create_section()

      {:ok, original} =
        Content.upsert_section_overview(section.id, user_role.id, "Original body.")

      {:ok, updated} =
        Content.upsert_section_overview(section.id, user_role.id, "Updated body.")

      assert updated.id == original.id
      assert updated.body == "Updated body."
    end

    test "refreshes generated_at on update" do
      user_role = create_user_role()
      section = create_section()

      old_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      # Manually insert a stale overview
      {:ok, stale} =
        %SectionOverview{}
        |> SectionOverview.changeset(%{
          section_id: section.id,
          user_role_id: user_role.id,
          body: "Old overview.",
          generated_at: old_time
        })
        |> Repo.insert()

      {:ok, refreshed} =
        Content.upsert_section_overview(section.id, user_role.id, "Fresh overview.")

      assert refreshed.id == stale.id
      assert DateTime.compare(refreshed.generated_at, old_time) == :gt
    end

    test "returns error changeset when body is blank" do
      user_role = create_user_role()
      section = create_section()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Content.upsert_section_overview(section.id, user_role.id, "")

      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "allows separate overviews per user for the same section" do
      user_role1 = create_user_role()
      user_role2 = create_user_role()
      section = create_section()

      {:ok, o1} = Content.upsert_section_overview(section.id, user_role1.id, "User1 view.")
      {:ok, o2} = Content.upsert_section_overview(section.id, user_role2.id, "User2 view.")

      assert o1.id != o2.id
      assert o1.body == "User1 view."
      assert o2.body == "User2 view."
    end
  end
end
