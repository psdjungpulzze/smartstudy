defmodule FunSheep.Questions.QuestionBankQueriesTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Questions}

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp make_course do
    {:ok, course} = Courses.create_course(%{name: "Biology 101", subject: "Biology", grade: "10"})
    course
  end

  defp make_chapter(course, attrs \\ %{}) do
    defaults = %{
      name: "Chapter #{System.unique_integer([:positive])}",
      position: 1,
      course_id: course.id
    }

    {:ok, ch} = Courses.create_chapter(Map.merge(defaults, attrs))
    ch
  end

  defp make_section(chapter, attrs \\ %{}) do
    defaults = %{
      name: "Section #{System.unique_integer([:positive])}",
      position: 1,
      chapter_id: chapter.id
    }

    {:ok, sec} = Courses.create_section(Map.merge(defaults, attrs))
    sec
  end

  defp make_question(course, attrs \\ %{}) do
    defaults = %{
      content: "Question #{System.unique_integer([:positive])}?",
      answer: "Answer",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id,
      validation_status: :passed
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  # ── list_chapter_section_counts/2 ─────────────────────────────────────────

  describe "list_chapter_section_counts/2" do
    test "returns empty map when course has no questions" do
      course = make_course()
      assert Questions.list_chapter_section_counts(course.id) == %{}
    end

    test "groups questions by chapter and section" do
      course = make_course()
      ch = make_chapter(course)
      sec1 = make_section(ch)
      sec2 = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec1.id})
      make_question(course, %{chapter_id: ch.id, section_id: sec1.id})
      make_question(course, %{chapter_id: ch.id, section_id: sec2.id})

      counts = Questions.list_chapter_section_counts(course.id)

      ch_data = counts[ch.id]
      assert ch_data.total == 3
      assert ch_data.sections[sec1.id] == 2
      assert ch_data.sections[sec2.id] == 1
    end

    test "groups questions with nil section_id under :none key" do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, section_id: nil})

      counts = Questions.list_chapter_section_counts(course.id)
      assert counts[ch.id].sections[:none] == 1
    end

    test "groups questions with nil chapter_id under :none key" do
      course = make_course()
      make_question(course, %{chapter_id: nil, section_id: nil})

      counts = Questions.list_chapter_section_counts(course.id)
      assert counts[:none].total == 1
    end

    test "respects statuses option — admin sees all" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec.id, validation_status: :passed})
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, validation_status: :pending})

      make_question(course, %{
        chapter_id: ch.id,
        section_id: sec.id,
        validation_status: :needs_review
      })

      student_counts = Questions.list_chapter_section_counts(course.id)

      admin_counts =
        Questions.list_chapter_section_counts(course.id,
          statuses: [:passed, :pending, :needs_review, :failed]
        )

      assert student_counts[ch.id].total == 1
      assert admin_counts[ch.id].total == 3
    end

    test "does not count questions from other courses" do
      course1 = make_course()
      course2 = make_course()
      ch = make_chapter(course1)
      make_question(course2, %{chapter_id: ch.id})

      assert Questions.list_chapter_section_counts(course1.id) == %{}
    end
  end

  # ── list_questions_for_section/2 ──────────────────────────────────────────

  describe "list_questions_for_section/2" do
    test "returns questions for the section, paginated" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      for _ <- 1..3, do: make_question(course, %{chapter_id: ch.id, section_id: sec.id})

      {questions, total} = Questions.list_questions_for_section(sec.id)

      assert total == 3
      assert length(questions) == 3
    end

    test "returns empty for section with no questions" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      {questions, total} = Questions.list_questions_for_section(sec.id)
      assert {questions, total} == {[], 0}
    end

    test "filters by difficulty" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec.id, difficulty: :easy})
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, difficulty: :hard})

      {questions, total} =
        Questions.list_questions_for_section(sec.id, filters: %{"difficulty" => "easy"})

      assert total == 1
      assert hd(questions).difficulty == :easy
    end

    test "respects statuses option — excludes non-passed by default" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec.id, validation_status: :passed})
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, validation_status: :pending})

      {_questions, total_student} = Questions.list_questions_for_section(sec.id)

      {_questions, total_admin} =
        Questions.list_questions_for_section(sec.id, statuses: [:passed, :pending])

      assert total_student == 1
      assert total_admin == 2
    end

    test "paginates correctly" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      for _ <- 1..(Questions.page_size() + 2),
          do: make_question(course, %{chapter_id: ch.id, section_id: sec.id})

      {page1, total} = Questions.list_questions_for_section(sec.id, page: 1)
      {page2, _} = Questions.list_questions_for_section(sec.id, page: 2)

      assert total == Questions.page_size() + 2
      assert length(page1) == Questions.page_size()
      assert length(page2) == 2
    end
  end

  # ── list_questions_for_chapter/2 ──────────────────────────────────────────

  describe "list_questions_for_chapter/2" do
    test "returns all questions for the chapter across sections" do
      course = make_course()
      ch = make_chapter(course)
      sec1 = make_section(ch)
      sec2 = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec1.id})
      make_question(course, %{chapter_id: ch.id, section_id: sec2.id})
      make_question(course, %{chapter_id: ch.id, section_id: nil})

      {questions, total} = Questions.list_questions_for_chapter(ch.id)
      assert total == 3
      assert length(questions) == 3
    end

    test "does not include questions from other chapters" do
      course = make_course()
      ch1 = make_chapter(course)
      ch2 = make_chapter(course)

      make_question(course, %{chapter_id: ch1.id})
      make_question(course, %{chapter_id: ch2.id})

      {_questions, total} = Questions.list_questions_for_chapter(ch1.id)
      assert total == 1
    end
  end

  # ── coverage_summary/1 ────────────────────────────────────────────────────

  describe "coverage_summary/1" do
    test "returns zeroed-out map for empty course" do
      course = make_course()
      summary = Questions.coverage_summary(course.id)

      assert summary.passed == 0
      assert summary.needs_review == 0
      assert summary.pending == 0
      assert summary.failed == 0
      assert summary.coverage_pct == 0.0
    end

    test "counts by_difficulty for passed questions" do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec.id, difficulty: :easy})
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, difficulty: :medium})
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, difficulty: :medium})

      summary = Questions.coverage_summary(course.id)
      assert summary.by_difficulty.easy == 1
      assert summary.by_difficulty.medium == 2
      assert summary.by_difficulty.hard == 0
    end

    test "counts validation status breakdowns" do
      course = make_course()
      ch = make_chapter(course)

      make_question(course, %{chapter_id: ch.id, validation_status: :passed})
      make_question(course, %{chapter_id: ch.id, validation_status: :needs_review})
      make_question(course, %{chapter_id: ch.id, validation_status: :pending})

      summary = Questions.coverage_summary(course.id)
      assert summary.passed == 1
      assert summary.needs_review == 1
      assert summary.pending == 1
    end

    test "coverage_pct reflects sections with at least one passed question" do
      course = make_course()
      ch = make_chapter(course)
      sec1 = make_section(ch)
      sec2 = make_section(ch)

      make_question(course, %{chapter_id: ch.id, section_id: sec1.id})
      # sec2 has no questions — total_sections = 2, sections_with_questions = 1

      summary = Questions.coverage_summary(course.id)
      assert summary.total_sections == 2
      assert summary.sections_with_questions == 1
      assert summary.coverage_pct == 50.0
    end
  end

  # ── page_size/0 ───────────────────────────────────────────────────────────

  describe "page_size/0" do
    test "returns a positive integer" do
      assert Questions.page_size() > 0
    end
  end
end
