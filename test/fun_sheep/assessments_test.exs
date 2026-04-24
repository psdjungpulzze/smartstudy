defmodule FunSheep.AssessmentsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments
  alias FunSheep.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "create_test_schedule/1" do
    test "creates a test schedule with valid attrs", %{user_role: ur, course: c, chapter: ch} do
      attrs = %{
        name: "Midterm Exam",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [ch.id]},
        user_role_id: ur.id,
        course_id: c.id
      }

      assert {:ok, schedule} = Assessments.create_test_schedule(attrs)
      assert schedule.name == "Midterm Exam"
      assert schedule.course_id == c.id
    end

    test "fails without required fields" do
      assert {:error, changeset} = Assessments.create_test_schedule(%{})
      assert errors_on(changeset) |> Map.has_key?(:name)
      assert errors_on(changeset) |> Map.has_key?(:test_date)
    end
  end

  describe "list_test_schedules_for_user/1" do
    test "returns schedules for user", %{user_role: ur, course: c, chapter: ch} do
      {:ok, _s} =
        Assessments.create_test_schedule(%{
          name: "Quiz 1",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      schedules = Assessments.list_test_schedules_for_user(ur.id)
      assert length(schedules) == 1
      assert hd(schedules).name == "Quiz 1"
    end

    test "does not return other users' schedules", %{course: c, chapter: ch} do
      other_user = ContentFixtures.create_user_role()

      {:ok, _s} =
        Assessments.create_test_schedule(%{
          name: "Other Quiz",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: other_user.id,
          course_id: c.id
        })

      my_user = ContentFixtures.create_user_role()
      schedules = Assessments.list_test_schedules_for_user(my_user.id)
      assert schedules == []
    end
  end

  describe "list_upcoming_schedules/2" do
    test "returns only future schedules", %{user_role: ur, course: c, chapter: ch} do
      # Future test
      {:ok, _future} =
        Assessments.create_test_schedule(%{
          name: "Future Test",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      # Past test
      {:ok, _past} =
        Assessments.create_test_schedule(%{
          name: "Past Test",
          test_date: Date.add(Date.utc_today(), -5),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      upcoming = Assessments.list_upcoming_schedules(ur.id)
      assert length(upcoming) == 1
      assert hd(upcoming).name == "Future Test"
    end

    test "respects days_ahead limit", %{user_role: ur, course: c, chapter: ch} do
      {:ok, _far} =
        Assessments.create_test_schedule(%{
          name: "Far Future",
          test_date: Date.add(Date.utc_today(), 60),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      upcoming = Assessments.list_upcoming_schedules(ur.id, 30)
      assert upcoming == []
    end
  end

  describe "primary test selection (pin / nearest-deadline)" do
    setup %{user_role: ur, course: c, chapter: ch} do
      {:ok, near} =
        Assessments.create_test_schedule(%{
          name: "Near",
          test_date: Date.add(Date.utc_today(), 5),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      {:ok, far} =
        Assessments.create_test_schedule(%{
          name: "Far",
          test_date: Date.add(Date.utc_today(), 30),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      %{near: near, far: far}
    end

    test "primary_test/1 defaults to the nearest-deadline test when nothing is pinned",
         %{user_role: ur, near: near} do
      assert %{id: id} = Assessments.primary_test(ur.id)
      assert id == near.id
    end

    test "pin_test/2 sets the pinned id and primary_test honors it",
         %{user_role: ur, far: far} do
      assert {:ok, _} = Assessments.pin_test(ur.id, far.id)
      assert Assessments.pinned_test_id(ur.id) == far.id
      assert %{id: id} = Assessments.primary_test(ur.id)
      assert id == far.id
    end

    test "unpin_test/1 clears the pin and primary reverts to nearest-deadline",
         %{user_role: ur, near: near, far: far} do
      {:ok, _} = Assessments.pin_test(ur.id, far.id)
      assert {:ok, _} = Assessments.unpin_test(ur.id)
      assert Assessments.pinned_test_id(ur.id) == nil
      assert %{id: id} = Assessments.primary_test(ur.id)
      assert id == near.id
    end

    test "primary_test/1 silently falls back when the pinned test is stale",
         %{user_role: ur, near: near, far: far} do
      {:ok, _} = Assessments.pin_test(ur.id, far.id)
      {:ok, _} = Assessments.delete_test_schedule(far)
      # Pinned row is now gone (on_delete: :nilify_all clears the FK)
      assert Assessments.pinned_test_id(ur.id) == nil
      assert %{id: id} = Assessments.primary_test(ur.id)
      assert id == near.id
    end

    test "pin_test/2 rejects a test owned by another user", %{course: c, chapter: ch} do
      other = ContentFixtures.create_user_role()

      {:ok, others_test} =
        Assessments.create_test_schedule(%{
          name: "Other's",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: other.id,
          course_id: c.id
        })

      me = ContentFixtures.create_user_role()
      assert {:error, :forbidden} = Assessments.pin_test(me.id, others_test.id)
    end

    test "primary_test/1 returns nil when no upcoming tests exist" do
      lonely = ContentFixtures.create_user_role()
      assert Assessments.primary_test(lonely.id) == nil
    end
  end

  describe "delete_test_schedule/1" do
    test "deletes a schedule", %{user_role: ur, course: c, chapter: ch} do
      {:ok, schedule} =
        Assessments.create_test_schedule(%{
          name: "To Delete",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{"chapter_ids" => [ch.id]},
          user_role_id: ur.id,
          course_id: c.id
        })

      assert {:ok, _} = Assessments.delete_test_schedule(schedule)

      assert_raise Ecto.NoResultsError, fn ->
        Assessments.get_test_schedule!(schedule.id)
      end
    end
  end
end
