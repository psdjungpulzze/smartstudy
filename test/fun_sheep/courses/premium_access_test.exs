defmodule FunSheep.Courses.PremiumAccessTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Courses
  alias FunSheep.Billing

  defp create_user_role do
    FunSheep.ContentFixtures.create_user_role()
  end

  defp create_course(attrs) do
    defaults = %{name: "Test Course", subject: "Biology", grade: "10"}

    {:ok, course} =
      %FunSheep.Courses.Course{}
      |> FunSheep.Courses.Course.changeset(Map.merge(defaults, attrs))
      |> FunSheep.Repo.insert()

    course
  end

  defp create_premium_catalog_course(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    user_role = create_user_role()

    create_course(
      Map.merge(
        %{
          is_premium_catalog: true,
          access_level: "standard",
          catalog_test_type: "sat",
          published_at: now,
          published_by_id: user_role.id
        },
        attrs
      )
    )
  end

  defp activate_subscription(user_role_id, plan) do
    {:ok, _} =
      Billing.activate_subscription(user_role_id, %{
        plan: plan,
        status: "active"
      })
  end

  describe "can_access_course?/2" do
    test "returns :ok for public courses without subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "public"})

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns :ok for preview courses without subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "preview"})

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns {:error, :requires_subscription} for standard course with free plan" do
      user_role = create_user_role()
      course = create_course(%{access_level: "standard"})

      # No subscription = free by default
      assert Courses.can_access_course?(user_role.id, course.id) ==
               {:error, :requires_subscription}
    end

    test "returns :ok for standard course with monthly subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "standard"})
      activate_subscription(user_role.id, "monthly")

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns :ok for standard course with annual subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "standard"})
      activate_subscription(user_role.id, "annual")

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns {:error, :requires_subscription} for premium course with monthly plan" do
      user_role = create_user_role()
      course = create_course(%{access_level: "premium"})
      activate_subscription(user_role.id, "monthly")

      assert Courses.can_access_course?(user_role.id, course.id) ==
               {:error, :requires_subscription}
    end

    test "returns :ok for enrolled user regardless of subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "premium"})

      # No subscription, but direct enrollment
      {:ok, _} = Courses.enroll_in_course(user_role.id, course.id, "gifted")

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns {:error, :requires_subscription} for expired enrollment with insufficient plan" do
      user_role = create_user_role()
      course = create_course(%{access_level: "standard"})

      past = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)

      {:ok, _} =
        Courses.enroll_in_course(user_role.id, course.id, "alacarte", expires_at: past)

      assert Courses.can_access_course?(user_role.id, course.id) ==
               {:error, :requires_subscription}
    end

    test "returns :ok for non-expired enrollment without subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "premium"})

      future = DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      {:ok, _} =
        Courses.enroll_in_course(user_role.id, course.id, "alacarte", expires_at: future)

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end

    test "returns :ok for permanent enrollment (no expires_at) without subscription" do
      user_role = create_user_role()
      course = create_course(%{access_level: "professional"})

      {:ok, _} = Courses.enroll_in_course(user_role.id, course.id, "gifted")

      assert Courses.can_access_course?(user_role.id, course.id) == :ok
    end
  end

  describe "list_premium_catalog/0" do
    test "returns only published premium catalog courses" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      admin = create_user_role()

      published = create_premium_catalog_course(%{catalog_test_type: "sat"})

      # Unpublished draft — should NOT appear
      _draft =
        create_course(%{
          is_premium_catalog: true,
          access_level: "standard",
          catalog_test_type: "act"
        })

      # Non-premium course with published_at — should NOT appear
      _regular =
        create_course(%{
          is_premium_catalog: false,
          access_level: "public",
          published_at: now,
          published_by_id: admin.id
        })

      results = Courses.list_premium_catalog()
      ids = Enum.map(results, & &1.id)

      assert published.id in ids
      assert length(Enum.filter(ids, &(&1 == published.id))) == 1
    end

    test "returns empty list when no published premium courses exist" do
      _draft = create_course(%{is_premium_catalog: true, access_level: "standard"})
      assert Courses.list_premium_catalog() == []
    end

    test "filters by test_type" do
      sat_course = create_premium_catalog_course(%{catalog_test_type: "sat"})
      _act_course = create_premium_catalog_course(%{catalog_test_type: "act"})

      sat_results = Courses.list_premium_catalog(test_type: "sat")
      sat_ids = Enum.map(sat_results, & &1.id)

      assert sat_course.id in sat_ids
      refute Enum.any?(sat_results, &(&1.catalog_test_type == "act"))
    end
  end

  describe "publish_course/2" do
    test "sets published_at and published_by_id" do
      admin = create_user_role()
      course = create_course(%{is_premium_catalog: true, access_level: "standard"})

      assert is_nil(course.published_at)
      assert is_nil(course.published_by_id)

      {:ok, updated} = Courses.publish_course(course.id, admin.id)

      assert updated.published_by_id == admin.id
      assert updated.published_at != nil
    end

    test "returns {:ok, course} on success" do
      admin = create_user_role()
      course = create_course(%{is_premium_catalog: true})

      assert {:ok, %FunSheep.Courses.Course{}} = Courses.publish_course(course.id, admin.id)
    end
  end
end
