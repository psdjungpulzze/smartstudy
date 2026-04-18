defmodule StudySmart.Export do
  @moduledoc """
  Export study materials to various formats.
  """

  @doc """
  Converts a study guide's content map to formatted plain text.
  """
  def export_study_guide_text(study_guide) do
    content = study_guide.content || %{}

    lines = [
      "# #{content["title"] || "Study Guide"}",
      "Course: #{content["generated_for"] || "N/A"}",
      "Test Date: #{content["test_date"] || "N/A"}",
      "Overall Readiness: #{content["aggregate_score"] || "N/A"}%",
      "",
      "---",
      ""
    ]

    section_lines =
      Enum.flat_map(content["sections"] || [], fn section ->
        header_lines = [
          "## #{section["chapter_name"]} (#{section["priority"] || "Normal"} Priority - #{section["score"] || 0}%)",
          ""
        ]

        topic_lines =
          Enum.map(section["review_topics"] || [], fn topic -> "- #{topic}" end)

        wrong_lines =
          if length(section["wrong_questions"] || []) > 0 do
            ["", "### Questions to Review", ""] ++
              Enum.flat_map(section["wrong_questions"] || [], fn q ->
                ["**Q:** #{q["content"]}", "**A:** #{q["answer"]}", ""]
              end)
          else
            []
          end

        header_lines ++ topic_lines ++ wrong_lines ++ [""]
      end)

    Enum.join(lines ++ section_lines, "\n")
  end

  @doc """
  Converts a readiness report to formatted plain text.
  """
  def export_readiness_report_text(test_schedule, readiness_score, chapters) do
    lines = [
      "# Test Readiness Report",
      "Test: #{test_schedule.name}",
      "Date: #{test_schedule.test_date}",
      "Overall Score: #{readiness_score.aggregate_score}%",
      "",
      "## Chapter Scores",
      ""
    ]

    chapter_lines =
      Enum.map(chapters, fn chapter ->
        score =
          get_chapter_score(readiness_score.chapter_scores, chapter.id)

        status =
          cond do
            score >= 70 -> "Ready"
            score >= 40 -> "Needs Work"
            true -> "Critical"
          end

        "- #{chapter.name}: #{score}% (#{status})"
      end)

    Enum.join(lines ++ chapter_lines, "\n")
  end

  defp get_chapter_score(nil, _chapter_id), do: 0.0

  defp get_chapter_score(chapter_scores, chapter_id) do
    # chapter_scores keys may be string or atom
    Map.get(chapter_scores, chapter_id, 0.0)
    |> case do
      score when is_number(score) -> score
      _ -> 0.0
    end
  end
end
