defmodule StudySmart.Learning.StudyGuideGenerator do
  @moduledoc """
  Generates structured study guides based on readiness scores.
  Identifies weak chapters/topics and produces review content.
  AI agent integration will be added in a future iteration.
  """

  alias StudySmart.{Assessments, Courses, Learning, Questions}

  @doc """
  Generates a study guide for a user and test schedule, persisting it.
  Returns {:ok, study_guide} or {:error, changeset}.
  """
  def generate(user_role_id, test_schedule_id) do
    schedule = Assessments.get_test_schedule_with_course!(test_schedule_id)
    readiness = Assessments.latest_readiness(user_role_id, test_schedule_id)
    course_with_chapters = Courses.get_course_with_chapters!(schedule.course_id)
    chapters = course_with_chapters.chapters

    weak_chapters = identify_weak_chapters(readiness, chapters)

    content = %{
      "title" => "Study Guide: #{schedule.name}",
      "generated_for" => schedule.course.name,
      "test_date" => Date.to_string(schedule.test_date),
      "aggregate_score" => (readiness && readiness.aggregate_score) || 0,
      "sections" =>
        Enum.map(weak_chapters, fn {chapter, score} ->
          wrong_questions = get_wrong_questions(user_role_id, chapter.id)

          %{
            "chapter_id" => chapter.id,
            "chapter_name" => chapter.name,
            "score" => score,
            "priority" => priority_label(score),
            "review_topics" => [
              "Review all concepts in #{chapter.name}",
              "Focus on questions you got wrong (#{length(wrong_questions)} questions)"
            ],
            "wrong_questions" =>
              Enum.map(wrong_questions, fn q ->
                %{"id" => q.id, "content" => q.content, "answer" => q.answer}
              end)
          }
        end)
    }

    Learning.create_study_guide(%{
      user_role_id: user_role_id,
      test_schedule_id: test_schedule_id,
      content: content,
      generated_at: DateTime.utc_now()
    })
  end

  @doc false
  def identify_weak_chapters(nil, chapters) do
    Enum.map(chapters, fn ch -> {ch, 0.0} end)
  end

  def identify_weak_chapters(readiness, chapters) do
    chapters
    |> Enum.map(fn ch ->
      score = Map.get(readiness.chapter_scores || %{}, ch.id, 0.0)
      {ch, score}
    end)
    |> Enum.filter(fn {_ch, score} -> score < 80.0 end)
    |> Enum.sort_by(fn {_ch, score} -> score end)
  end

  @doc false
  def priority_label(score) when score < 30, do: "Critical"
  def priority_label(score) when score < 50, do: "High"
  def priority_label(score) when score < 70, do: "Medium"
  def priority_label(_), do: "Low"

  defp get_wrong_questions(user_role_id, chapter_id) do
    Questions.list_wrong_questions_for_chapter(user_role_id, chapter_id)
  end
end
