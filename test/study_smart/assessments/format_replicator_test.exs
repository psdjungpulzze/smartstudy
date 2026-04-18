defmodule StudySmart.Assessments.FormatReplicatorTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Assessments.FormatReplicator
  alias StudySmart.{Assessments, Questions}
  alias StudySmart.ContentFixtures

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      StudySmart.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    # Create questions of different types
    for i <- 1..5 do
      Questions.create_question(%{
        content: "MC Question #{i}",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Yes", "B" => "No"},
        course_id: course.id,
        chapter_id: chapter.id
      })
    end

    for i <- 1..3 do
      Questions.create_question(%{
        content: "TF Question #{i}",
        answer: "True",
        question_type: :true_false,
        difficulty: :medium,
        course_id: course.id,
        chapter_id: chapter.id
      })
    end

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "generate_practice_test/3" do
    test "creates correct section structure", %{
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, template} =
        Assessments.create_test_format_template(%{
          name: "Test Template",
          structure: %{
            "sections" => [
              %{
                "name" => "Multiple Choice",
                "question_type" => "multiple_choice",
                "count" => 3,
                "points_per_question" => 2,
                "chapter_ids" => [chapter.id]
              },
              %{
                "name" => "True/False",
                "question_type" => "true_false",
                "count" => 2,
                "points_per_question" => 1,
                "chapter_ids" => [chapter.id]
              }
            ],
            "time_limit_minutes" => 30
          }
        })

      result = FormatReplicator.generate_practice_test(template.id, course.id, ur.id)

      assert length(result.sections) == 2
      assert result.time_limit == 30

      [mc_section, tf_section] = result.sections
      assert mc_section["name"] == "Multiple Choice"
      assert mc_section["actual_count"] <= 3
      assert mc_section["points_per_question"] == 2

      assert tf_section["name"] == "True/False"
      assert tf_section["actual_count"] <= 2
      assert tf_section["points_per_question"] == 1
    end

    test "respects question type and count", %{
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, template} =
        Assessments.create_test_format_template(%{
          name: "MC Template",
          structure: %{
            "sections" => [
              %{
                "name" => "MC Only",
                "question_type" => "multiple_choice",
                "count" => 2,
                "chapter_ids" => [chapter.id]
              }
            ]
          }
        })

      result = FormatReplicator.generate_practice_test(template.id, course.id, ur.id)
      [section] = result.sections
      assert section["actual_count"] == 2
      assert section["question_type"] == "multiple_choice"
    end

    test "handles empty question pool gracefully", %{user_role: ur} do
      empty_course = ContentFixtures.create_course(%{created_by_id: ur.id, name: "Empty"})

      {:ok, template} =
        Assessments.create_test_format_template(%{
          name: "Empty Template",
          structure: %{
            "sections" => [
              %{
                "name" => "Section 1",
                "question_type" => "multiple_choice",
                "count" => 5,
                "chapter_ids" => []
              }
            ]
          }
        })

      result = FormatReplicator.generate_practice_test(template.id, empty_course.id, ur.id)
      [section] = result.sections
      assert section["actual_count"] == 0
      assert section["questions"] == []
      assert result.total_questions == 0
    end
  end
end
