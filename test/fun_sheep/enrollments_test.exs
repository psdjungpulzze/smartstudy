defmodule FunSheep.EnrollmentsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Enrollments, Accounts, Courses, Geo}
  alias FunSheep.Enrollments.StudentCourse

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp create_student(extra \\ %{}) do
    uid = System.unique_integer([:positive])

    defaults = %{
      interactor_user_id: "enroll_student_#{uid}",
      role: :student,
      email: "enroll_s#{uid}@test.com",
      display_name: "Enroll Student"
    }

    {:ok, ur} = Accounts.create_user_role(Map.merge(defaults, extra))
    ur
  end

  defp create_school do
    {:ok, country} =
      Geo.create_country(%{
        name: "US-E#{System.unique_integer()}",
        code: "U#{System.unique_integer()}"
      })

    {:ok, state} =
      Geo.create_state(%{name: "CA-E#{System.unique_integer()}", country_id: country.id})

    {:ok, district} =
      Geo.create_district(%{name: "LA-E#{System.unique_integer()}", state_id: state.id})

    {:ok, school} =
      Geo.create_school(%{
        name: "Test School #{System.unique_integer()}",
        district_id: district.id
      })

    school
  end

  defp create_course(attrs \\ %{}) do
    defaults = %{name: "Enroll Course #{System.unique_integer()}", subject: "Math", grade: "10"}
    {:ok, course} = Courses.create_course(Map.merge(defaults, attrs))
    course
  end

  # ── enroll/3 ───────────────────────────────────────────────────────────────

  describe "enroll/3" do
    test "happy path creates an active StudentCourse" do
      student = create_student()
      course = create_course()

      assert {:ok, %StudentCourse{} = sc} = Enrollments.enroll(student.id, course.id)
      assert sc.user_role_id == student.id
      assert sc.course_id == course.id
      assert sc.status == "active"
      assert sc.source == "self_enrolled"
      assert sc.enrolled_at != nil
    end

    test "duplicate enrollment is idempotent (on_conflict: :nothing)" do
      student = create_student()
      course = create_course()

      assert {:ok, _sc1} = Enrollments.enroll(student.id, course.id)
      # Second call should succeed (on_conflict: :nothing returns nil struct)
      assert {:ok, _} = Enrollments.enroll(student.id, course.id)

      # Only one row exists
      rows =
        Repo.all(
          from(sc in StudentCourse,
            where: sc.user_role_id == ^student.id and sc.course_id == ^course.id
          )
        )

      assert length(rows) == 1
    end

    test "enroll with explicit source persists the source" do
      student = create_student()
      course = create_course()

      assert {:ok, %StudentCourse{source: "onboarding"}} =
               Enrollments.enroll(student.id, course.id, "onboarding")
    end

    test "invalid source returns changeset error" do
      student = create_student()
      course = create_course()

      assert {:error, changeset} = Enrollments.enroll(student.id, course.id, "bad_source")
      assert {:source, _} = List.keyfind(changeset.errors, :source, 0)
    end
  end

  # ── bulk_enroll/3 ──────────────────────────────────────────────────────────

  describe "bulk_enroll/3" do
    test "enrolls multiple courses and returns the list" do
      student = create_student()
      c1 = create_course()
      c2 = create_course()
      c3 = create_course()

      assert {:ok, enrolled} = Enrollments.bulk_enroll(student.id, [c1.id, c2.id, c3.id])
      assert length(enrolled) == 3
      enrolled_course_ids = Enum.map(enrolled, & &1.course_id)
      assert c1.id in enrolled_course_ids
      assert c2.id in enrolled_course_ids
      assert c3.id in enrolled_course_ids
    end

    test "empty list returns ok with empty list" do
      student = create_student()
      assert {:ok, []} = Enrollments.bulk_enroll(student.id, [])
    end

    test "uses onboarding source by default" do
      student = create_student()
      course = create_course()

      {:ok, [sc]} = Enrollments.bulk_enroll(student.id, [course.id])
      assert sc.source == "onboarding"
    end
  end

  # ── drop/2 ─────────────────────────────────────────────────────────────────

  describe "drop/2" do
    test "happy path sets status to dropped" do
      student = create_student()
      course = create_course()
      {:ok, _sc} = Enrollments.enroll(student.id, course.id)

      assert {:ok, updated_sc} = Enrollments.drop(student.id, course.id)
      assert updated_sc.status == "dropped"
    end

    test "returns :not_found when the student is not enrolled" do
      student = create_student()
      course = create_course()

      assert {:error, :not_found} = Enrollments.drop(student.id, course.id)
    end
  end

  # ── list_for_student/2 ─────────────────────────────────────────────────────

  describe "list_for_student/2" do
    test "returns active enrollments with course preloaded" do
      student = create_student()
      c1 = create_course(%{name: "Math 101"})
      c2 = create_course(%{name: "Science 101"})
      Enrollments.enroll(student.id, c1.id)
      Enrollments.enroll(student.id, c2.id)

      results = Enrollments.list_for_student(student.id)
      assert length(results) == 2
      # courses are preloaded
      assert Enum.all?(results, fn sc -> %Courses.Course{} = sc.course end)
    end

    test "does not return dropped enrollments when listing active" do
      student = create_student()
      course = create_course()
      Enrollments.enroll(student.id, course.id)
      Enrollments.drop(student.id, course.id)

      results = Enrollments.list_for_student(student.id)
      assert results == []
    end

    test "status filter works" do
      student = create_student()
      course = create_course()
      Enrollments.enroll(student.id, course.id)
      Enrollments.drop(student.id, course.id)

      dropped = Enrollments.list_for_student(student.id, status: "dropped")
      assert length(dropped) == 1
      assert hd(dropped).status == "dropped"
    end
  end

  # ── enrolled?/2 ────────────────────────────────────────────────────────────

  describe "enrolled?/2" do
    test "returns true when student is actively enrolled" do
      student = create_student()
      course = create_course()
      Enrollments.enroll(student.id, course.id)

      assert Enrollments.enrolled?(student.id, course.id) == true
    end

    test "returns false when student is not enrolled" do
      student = create_student()
      course = create_course()

      assert Enrollments.enrolled?(student.id, course.id) == false
    end

    test "returns false when enrollment is dropped" do
      student = create_student()
      course = create_course()
      Enrollments.enroll(student.id, course.id)
      Enrollments.drop(student.id, course.id)

      assert Enrollments.enrolled?(student.id, course.id) == false
    end
  end
end
