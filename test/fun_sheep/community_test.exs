defmodule FunSheep.CommunityTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Accounts, Community, Courses}

  # ── Test helpers ──────────────────────────────────────────────────────

  defp create_user_role(attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "student_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test Student"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp create_course(attrs \\ %{}) do
    defaults = %{name: "Test Course", subject: "Math", grade: "10"}
    {:ok, course} = Courses.create_course(Map.merge(defaults, attrs))
    course
  end

  # ── react_to_course/3 ────────────────────────────────────────────────

  describe "react_to_course/3" do
    test "creates a new like" do
      user_role = create_user_role()
      course = create_course()

      assert {:ok, "like"} = Community.react_to_course(user_role.id, course.id, "like")
    end

    test "creates a new dislike" do
      user_role = create_user_role()
      course = create_course()

      assert {:ok, "dislike"} = Community.react_to_course(user_role.id, course.id, "dislike")
    end

    test "updates existing reaction from like to dislike" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")

      assert Community.get_user_reaction(user_role.id, course.id) == "like"

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "dislike")

      assert Community.get_user_reaction(user_role.id, course.id) == "dislike"
    end

    test "updates existing reaction from dislike to like" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "dislike")
      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")

      assert Community.get_user_reaction(user_role.id, course.id) == "like"
    end

    test "reapplying the same reaction is idempotent" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")
      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")

      # Still only one reaction record
      import Ecto.Query

      count =
        FunSheep.Repo.aggregate(
          from(l in FunSheep.Community.ContentLike, where: l.course_id == ^course.id),
          :count
        )

      assert count == 1
    end

    test "multiple users can react to the same course independently" do
      user_role_a = create_user_role()
      user_role_b = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role_a.id, course.id, "like")
      {:ok, _} = Community.react_to_course(user_role_b.id, course.id, "dislike")

      assert Community.get_user_reaction(user_role_a.id, course.id) == "like"
      assert Community.get_user_reaction(user_role_b.id, course.id) == "dislike"
    end
  end

  # ── get_user_reaction/2 ──────────────────────────────────────────────

  describe "get_user_reaction/2" do
    test "returns nil when no reaction exists" do
      user_role = create_user_role()
      course = create_course()

      assert is_nil(Community.get_user_reaction(user_role.id, course.id))
    end

    test "returns 'like' after liking" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")

      assert Community.get_user_reaction(user_role.id, course.id) == "like"
    end

    test "returns 'dislike' after disliking" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "dislike")

      assert Community.get_user_reaction(user_role.id, course.id) == "dislike"
    end
  end

  # ── recompute_course_quality_score/1 ────────────────────────────────

  describe "recompute_course_quality_score/1" do
    test "score starts at 0.0 with no interactions" do
      course = create_course()

      {:ok, updated} = Community.recompute_course_quality_score(course.id)

      assert updated.quality_score == 0.0
    end

    test "score increases after a like" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "like")
      updated = Courses.get_course!(course.id)

      assert updated.quality_score > 0.0
      assert updated.like_count == 1
      assert updated.dislike_count == 0
    end

    test "score decreases after a dislike" do
      user_role = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role.id, course.id, "dislike")
      updated = Courses.get_course!(course.id)

      assert updated.quality_score < 0.0
      assert updated.like_count == 0
      assert updated.dislike_count == 1
    end

    test "like_count and dislike_count reflect real reactions" do
      user_role_a = create_user_role()
      user_role_b = create_user_role()
      user_role_c = create_user_role()
      course = create_course()

      {:ok, _} = Community.react_to_course(user_role_a.id, course.id, "like")
      {:ok, _} = Community.react_to_course(user_role_b.id, course.id, "like")
      {:ok, _} = Community.react_to_course(user_role_c.id, course.id, "dislike")

      updated = Courses.get_course!(course.id)

      assert updated.like_count == 2
      assert updated.dislike_count == 1
    end

    test "sets quality_last_computed_at" do
      course = create_course()

      {:ok, updated} = Community.recompute_course_quality_score(course.id)

      assert not is_nil(updated.quality_last_computed_at)
    end

    test "visibility_state is 'boosted' for new content" do
      course = create_course()

      {:ok, updated} = Community.recompute_course_quality_score(course.id)

      # New courses (< 72h old) get boosted regardless of score
      assert updated.visibility_state == "boosted"
    end
  end

  # ── ranking_score/1 ──────────────────────────────────────────────────

  describe "ranking_score/1" do
    test "new courses rank higher than old courses with the same quality_score" do
      # Simulate a new course (just inserted) vs an old course
      new_course = create_course()
      # Manually set inserted_at to 2 weeks ago to simulate old course
      old_inserted_at = DateTime.add(DateTime.utc_now(), -14 * 24 * 3600, :second)

      {:ok, old_course} =
        Courses.create_course(%{name: "Old Course", subject: "Science", grade: "10"})

      import Ecto.Query

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^old_course.id),
        set: [inserted_at: DateTime.truncate(old_inserted_at, :second), quality_score: 10.0]
      )

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^new_course.id),
        set: [quality_score: 10.0]
      )

      new_course = Courses.get_course!(new_course.id)
      old_course = Courses.get_course!(old_course.id)

      assert Community.ranking_score(new_course) > Community.ranking_score(old_course)
    end

    test "old course with zero attempts decays over time" do
      {:ok, course} =
        Courses.create_course(%{name: "Stale Course", subject: "History", grade: "9"})

      old_inserted_at =
        DateTime.add(DateTime.utc_now(), -5 * 7 * 24 * 3600, :second)

      import Ecto.Query

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^course.id),
        set: [
          inserted_at: DateTime.truncate(old_inserted_at, :second),
          quality_score: 50.0,
          attempt_count: 0
        ]
      )

      course = Courses.get_course!(course.id)

      # Ranking score should be less than the raw quality_score due to decay
      assert Community.ranking_score(course) < course.quality_score
    end
  end

  # ── mark_dormant_courses/0 ────────────────────────────────────────────

  describe "mark_dormant_courses/0" do
    test "marks old zero-activity courses as 'reduced'" do
      {:ok, course} =
        Courses.create_course(%{name: "Old Inactive Course", subject: "Art", grade: "7"})

      # Backdate inserted_at and quality_last_computed_at to 91 days ago
      old_ts = DateTime.add(DateTime.utc_now(), -91 * 24 * 3600, :second)

      import Ecto.Query

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^course.id),
        set: [
          inserted_at: DateTime.truncate(old_ts, :second),
          quality_last_computed_at: DateTime.truncate(old_ts, :second),
          attempt_count: 0,
          visibility_state: "normal"
        ]
      )

      Community.mark_dormant_courses()

      updated = Courses.get_course!(course.id)
      assert updated.visibility_state == "reduced"
      assert not is_nil(updated.dormant_at)
    end

    test "does not mark new courses as dormant" do
      course = create_course()

      Community.mark_dormant_courses()

      updated = Courses.get_course!(course.id)
      # New course should remain "normal" (it's less than 90 days old)
      assert updated.visibility_state == "normal"
      assert is_nil(updated.dormant_at)
    end

    test "does not mark courses with recent activity as dormant" do
      {:ok, course} =
        Courses.create_course(%{name: "Active Old Course", subject: "PE", grade: "8"})

      old_inserted = DateTime.add(DateTime.utc_now(), -100 * 24 * 3600, :second)
      recent_computed = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      import Ecto.Query

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^course.id),
        set: [
          inserted_at: DateTime.truncate(old_inserted, :second),
          quality_last_computed_at: DateTime.truncate(recent_computed, :second),
          attempt_count: 0,
          visibility_state: "normal"
        ]
      )

      Community.mark_dormant_courses()

      updated = Courses.get_course!(course.id)
      # Recent quality_last_computed_at should protect it from being dormant-flagged
      assert updated.visibility_state == "normal"
    end

    test "does not overwrite delisted courses" do
      {:ok, course} =
        Courses.create_course(%{name: "Delisted Course", subject: "Music", grade: "6"})

      old_ts = DateTime.add(DateTime.utc_now(), -91 * 24 * 3600, :second)

      import Ecto.Query

      FunSheep.Repo.update_all(
        from(c in FunSheep.Courses.Course, where: c.id == ^course.id),
        set: [
          inserted_at: DateTime.truncate(old_ts, :second),
          quality_last_computed_at: DateTime.truncate(old_ts, :second),
          attempt_count: 0,
          visibility_state: "delisted"
        ]
      )

      Community.mark_dormant_courses()

      updated = Courses.get_course!(course.id)
      assert updated.visibility_state == "delisted"
    end
  end
end
