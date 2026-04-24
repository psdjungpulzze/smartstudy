defmodule FunSheep.Courses.CourseEnrollmentTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Courses
  alias FunSheep.Courses.CourseEnrollment

  defp create_user_role do
    FunSheep.ContentFixtures.create_user_role()
  end

  defp create_course do
    FunSheep.ContentFixtures.create_course()
  end

  describe "changeset/2" do
    test "valid with required fields" do
      user_role = create_user_role()
      course = create_course()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        user_role_id: user_role.id,
        course_id: course.id,
        access_type: "subscription",
        access_granted_at: now
      }

      changeset = CourseEnrollment.changeset(%CourseEnrollment{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = CourseEnrollment.changeset(%CourseEnrollment{}, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.user_role_id
      assert "can't be blank" in errors.course_id
      assert "can't be blank" in errors.access_type
      assert "can't be blank" in errors.access_granted_at
    end

    test "rejects invalid access_type" do
      user_role = create_user_role()
      course = create_course()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        CourseEnrollment.changeset(%CourseEnrollment{}, %{
          user_role_id: user_role.id,
          course_id: course.id,
          access_type: "invalid_type",
          access_granted_at: now
        })

      errors = errors_on(changeset)
      assert "is invalid" in errors.access_type
    end

    test "accepts all valid access types" do
      user_role = create_user_role()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for access_type <- CourseEnrollment.access_types() do
        course = create_course()

        changeset =
          CourseEnrollment.changeset(%CourseEnrollment{}, %{
            user_role_id: user_role.id,
            course_id: course.id,
            access_type: access_type,
            access_granted_at: now
          })

        assert changeset.valid?, "Expected valid changeset for access_type=#{access_type}"
      end
    end

    test "optional fields access_expires_at and purchase_reference" do
      user_role = create_user_role()
      course = create_course()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      expires = DateTime.add(now, 90, :day)

      changeset =
        CourseEnrollment.changeset(%CourseEnrollment{}, %{
          user_role_id: user_role.id,
          course_id: course.id,
          access_type: "alacarte",
          access_granted_at: now,
          access_expires_at: expires,
          purchase_reference: "ch_test_abc123"
        })

      assert changeset.valid?
    end
  end

  describe "enroll_in_course/4" do
    test "creates an enrollment" do
      user_role = create_user_role()
      course = create_course()

      assert {:ok, enrollment} = Courses.enroll_in_course(user_role.id, course.id, "free")
      assert enrollment.user_role_id == user_role.id
      assert enrollment.course_id == course.id
      assert enrollment.access_type == "free"
      assert enrollment.access_granted_at != nil
      assert enrollment.access_expires_at == nil
    end

    test "creates enrollment with expiry and purchase reference" do
      user_role = create_user_role()
      course = create_course()
      expires = DateTime.add(DateTime.utc_now(), 365, :day) |> DateTime.truncate(:second)

      assert {:ok, enrollment} =
               Courses.enroll_in_course(user_role.id, course.id, "alacarte",
                 expires_at: expires,
                 purchase_reference: "pi_test_123"
               )

      assert enrollment.access_expires_at == expires
      assert enrollment.purchase_reference == "pi_test_123"
    end

    test "does not raise on duplicate enrollment (on_conflict: :nothing)" do
      user_role = create_user_role()
      course = create_course()

      assert {:ok, _} = Courses.enroll_in_course(user_role.id, course.id, "free")
      # Second call should not raise or return an error
      assert {:ok, _} = Courses.enroll_in_course(user_role.id, course.id, "subscription")
    end
  end

  describe "get_enrollment/2" do
    test "returns enrollment when one exists" do
      user_role = create_user_role()
      course = create_course()
      {:ok, created} = Courses.enroll_in_course(user_role.id, course.id, "gifted")

      result = Courses.get_enrollment(user_role.id, course.id)
      assert result.id == created.id
    end

    test "returns nil when no enrollment exists" do
      user_role = create_user_role()
      course = create_course()

      assert Courses.get_enrollment(user_role.id, course.id) == nil
    end
  end

  describe "unique constraint" do
    test "cannot insert two enrollments for the same user and course via the database" do
      user_role = create_user_role()
      course = create_course()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} = Courses.enroll_in_course(user_role.id, course.id, "free")

      # Bypass on_conflict: :nothing by using a direct insert to test the DB constraint
      result =
        %CourseEnrollment{}
        |> CourseEnrollment.changeset(%{
          user_role_id: user_role.id,
          course_id: course.id,
          access_type: "subscription",
          access_granted_at: now
        })
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "has already been taken" in errors_on(changeset).user_role_id
    end
  end
end
