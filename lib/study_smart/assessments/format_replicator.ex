defmodule StudySmart.Assessments.FormatReplicator do
  @moduledoc """
  Generates practice tests matching a specific test format template.
  Same question types, counts, sections, and point distribution.
  """

  alias StudySmart.Assessments
  alias StudySmart.Questions

  @doc """
  Generates a practice test structure matching the given template.

  Returns a map with sections, each containing selected question IDs
  matching the template's question type, count, and chapter scope.
  """
  def generate_practice_test(template_id, course_id, _user_role_id) do
    template = Assessments.get_test_format_template!(template_id)
    structure = template.structure || %{}

    sections =
      Enum.map(structure["sections"] || [], fn section ->
        questions =
          select_questions_for_section(
            course_id,
            section["question_type"],
            section["count"],
            section["chapter_ids"] || []
          )

        %{
          "name" => section["name"],
          "question_type" => section["question_type"],
          "target_count" => section["count"],
          "actual_count" => length(questions),
          "points_per_question" => section["points_per_question"] || 1,
          "questions" => Enum.map(questions, & &1.id)
        }
      end)

    %{
      template_id: template_id,
      course_id: course_id,
      sections: sections,
      time_limit: structure["time_limit_minutes"],
      total_questions: Enum.sum(Enum.map(sections, & &1["actual_count"])),
      total_points:
        Enum.sum(
          Enum.map(sections, fn s ->
            s["actual_count"] * s["points_per_question"]
          end)
        )
    }
  end

  defp select_questions_for_section(course_id, question_type, count, chapter_ids) do
    filters =
      if question_type && question_type != "" do
        %{"question_type" => question_type}
      else
        %{}
      end

    questions =
      if chapter_ids != [] do
        Enum.flat_map(chapter_ids, fn ch_id ->
          Questions.list_questions_by_course(
            course_id,
            Map.put(filters, "chapter_id", ch_id)
          )
        end)
        |> Enum.uniq_by(& &1.id)
      else
        Questions.list_questions_by_course(course_id, filters)
      end

    questions
    |> Enum.shuffle()
    |> Enum.take(count || 10)
  end
end
