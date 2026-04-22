defmodule FunSheep.Assessments.ScopeReadinessTest do
  @moduledoc """
  Covers every return shape of `FunSheep.Assessments.ScopeReadiness.check/1`:
  `:ready`, `:scope_empty`, `:scope_partial`, `{:course_not_ready, stage}`,
  `{:course_failed, reason}`.

  Scope-first semantics: if the inventory is sufficient, the student is let
  in regardless of `course.processing_status`. Course status only decides
  how we *explain* a block.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Assessments
  alias FunSheep.Assessments.ScopeReadiness
  alias FunSheep.{Courses, ContentFixtures, Questions, Repo}

  @min ScopeReadiness.min_questions_per_chapter()

  defp passed_question(course, chapter, section, idx) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: "Q#{idx}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :medium,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :ai_classified
      })

    q
  end

  defp pending_question(course, chapter, idx) do
    {:ok, q} =
      Questions.create_question(%{
        validation_status: :pending,
        content: "Pending Q#{idx}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :medium,
        options: %{"A" => "a", "B" => "b"},
        course_id: course.id,
        chapter_id: chapter.id,
        classification_status: :uncategorized
      })

    q
  end

  defp mk_schedule(user_role, course, chapter_ids) do
    {:ok, schedule} =
      Assessments.create_test_schedule(%{
        name: "Finals",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => chapter_ids},
        user_role_id: user_role.id,
        course_id: course.id
      })

    schedule
  end

  defp update_status(course, status) do
    {:ok, updated} =
      course
      |> Courses.Course.changeset(%{processing_status: status})
      |> Repo.update()

    updated
  end

  describe "check/1" do
    test "returns :ready when every in-scope chapter has enough visible + adaptive questions" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      for i <- 1..@min, do: passed_question(course, chapter, section, i)

      schedule = mk_schedule(user_role, course, [chapter.id])

      assert ScopeReadiness.check(schedule) == :ready
    end

    test ":ready overrides a non-ready course.processing_status when inventory is sufficient" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      for i <- 1..@min, do: passed_question(course, chapter, section, i)

      # Course still "validating" in the status machine, but questions ARE
      # already visible. Scope-first logic must let the student in.
      _ = update_status(course, "validating")
      schedule = mk_schedule(user_role, course, [chapter.id])

      assert ScopeReadiness.check(schedule) == :ready
    end

    test "returns {:scope_empty, ids} when course is ready but no chapter has questions" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "ready")
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, _section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      # No passed/classified questions inserted.
      schedule = mk_schedule(user_role, course, [chapter.id])

      assert {:scope_empty, [chapter_id]} = ScopeReadiness.check(schedule)
      assert chapter_id == chapter.id
    end

    test "returns {:scope_partial, ...} when some scope chapters are ready and some aren't" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "ready")

      {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
      {:ok, sec1} = Courses.create_section(%{name: "S", position: 1, chapter_id: ch1.id})

      {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})
      {:ok, _sec2} = Courses.create_section(%{name: "S", position: 1, chapter_id: ch2.id})

      for i <- 1..@min, do: passed_question(course, ch1, sec1, i)
      # ch2 has nothing

      schedule = mk_schedule(user_role, course, [ch1.id, ch2.id])

      assert {:scope_partial, %{ready: ready, missing: missing}} =
               ScopeReadiness.check(schedule)

      assert ready == [ch1.id]
      assert missing == [ch2.id]
    end

    test "returns {:course_not_ready, stage} when inventory insufficient and course is processing" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "generating")

      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, _section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      schedule = mk_schedule(user_role, course, [chapter.id])

      assert ScopeReadiness.check(schedule) == {:course_not_ready, :generating}
    end

    test "returns {:course_failed, reason} when inventory insufficient and course failed" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, course} =
        course
        |> Courses.Course.changeset(%{
          processing_status: "failed",
          processing_step: "AI service unavailable"
        })
        |> Repo.update()

      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, _section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      schedule = mk_schedule(user_role, course, [chapter.id])

      assert {:course_failed, "AI service unavailable"} = ScopeReadiness.check(schedule)
    end

    test "ignores unclassified questions even when validation passed" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "ready")
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})

      # Passed-but-uncategorized questions are NOT adaptive-eligible
      for i <- 1..@min, do: pending_question(course, chapter, i)

      schedule = mk_schedule(user_role, course, [chapter.id])

      assert {:scope_empty, _} = ScopeReadiness.check(schedule)
    end

    test "empty scope is treated as scope_empty (course ready)" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "ready")
      schedule = mk_schedule(user_role, course, [])

      assert ScopeReadiness.check(schedule) == {:scope_empty, []}
    end

    test "unknown processing_status buckets as :pending (still blocks with informative stage)" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      course = update_status(course, "some_unknown_status")
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      schedule = mk_schedule(user_role, course, [chapter.id])

      assert ScopeReadiness.check(schedule) == {:course_not_ready, :pending}
    end
  end

  describe "chapters_needing_generation/1" do
    test "returns every chapter below the threshold" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch1", position: 1, course_id: course.id})
      {:ok, sec1} = Courses.create_section(%{name: "S", position: 1, chapter_id: ch1.id})
      {:ok, ch2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

      for i <- 1..@min, do: passed_question(course, ch1, sec1, i)
      schedule = mk_schedule(user_role, course, [ch1.id, ch2.id])

      assert ScopeReadiness.chapters_needing_generation(schedule) == [ch2.id]
    end

    test "returns [] for a fully-ready scope" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})
      {:ok, section} = Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      for i <- 1..@min, do: passed_question(course, chapter, section, i)
      schedule = mk_schedule(user_role, course, [chapter.id])

      assert ScopeReadiness.chapters_needing_generation(schedule) == []
    end
  end
end
