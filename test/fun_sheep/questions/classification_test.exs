defmodule FunSheep.Questions.ClassificationTest do
  @moduledoc """
  Tests the classification foundation backing North Star I-1 (fine-grained
  skill tags) and I-15 (honest diagnostic filtering).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Questions, Repo}
  alias FunSheep.Questions.Question

  defp setup_course do
    {:ok, course} = Courses.create_course(%{name: "Math 101", subject: "Math", grade: "10"})
    {:ok, chapter} = Courses.create_chapter(%{name: "Fractions", position: 1, course_id: course.id})
    {:ok, section} = Courses.create_section(%{name: "Adding Fractions", position: 1, chapter_id: chapter.id})
    %{course: course, chapter: chapter, section: section}
  end

  defp insert_question(course, attrs) do
    defaults = %{
      content: "Q",
      answer: "A",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id,
      validation_status: :passed
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  describe "tagged_for_adaptive/1" do
    test "includes only section-tagged + trusted-classification questions" do
      %{course: course, chapter: chapter, section: section} = setup_course()

      eligible =
        insert_question(course, %{chapter_id: chapter.id, section_id: section.id, classification_status: :admin_reviewed})

      ai_tagged =
        insert_question(course, %{chapter_id: chapter.id, section_id: section.id, classification_status: :ai_classified})

      _low =
        insert_question(course, %{chapter_id: chapter.id, section_id: section.id, classification_status: :low_confidence})

      _untagged =
        insert_question(course, %{chapter_id: chapter.id, classification_status: :uncategorized})

      ids =
        Question
        |> Questions.tagged_for_adaptive()
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert Enum.sort([eligible.id, ai_tagged.id]) == ids
    end
  end

  describe "classification_coverage/1" do
    test "counts tagged / untagged / low-confidence per course and per chapter" do
      %{course: course, chapter: chapter, section: section} = setup_course()

      insert_question(course, %{chapter_id: chapter.id, section_id: section.id, classification_status: :admin_reviewed})
      insert_question(course, %{chapter_id: chapter.id, section_id: section.id, classification_status: :ai_classified})
      insert_question(course, %{chapter_id: chapter.id, classification_status: :low_confidence})
      insert_question(course, %{chapter_id: chapter.id, classification_status: :uncategorized})

      report = Questions.classification_coverage(course.id)

      assert report.total == 4
      assert report.tagged == 2
      assert report.untagged == 1
      assert report.low_confidence == 1

      [chapter_row] = report.by_chapter
      assert chapter_row.chapter_id == chapter.id
    end
  end

  describe "question schema defaults" do
    test "new questions default to :uncategorized" do
      %{course: course} = setup_course()
      q = insert_question(course, %{})
      assert q.classification_status == :uncategorized
      assert is_nil(q.classification_confidence)
      assert is_nil(q.classified_at)
    end
  end
end
