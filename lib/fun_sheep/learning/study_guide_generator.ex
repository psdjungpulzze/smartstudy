defmodule FunSheep.Learning.StudyGuideGenerator do
  @moduledoc """
  Generates structured study guides based on readiness scores.

  Produces a rich study guide with:
  - Daily study plan distributed across remaining days until test
  - Per-chapter breakdown with attempt stats and source material refs
  - Enriched wrong questions with difficulty, type, and attempt counts
  - Progress tracking structure for the UI to update

  AI-generated summaries and per-question explanations are handled
  on-demand by `FunSheep.Learning.StudyGuideAI`.
  """

  alias FunSheep.{Assessments, Courses, Learning, Questions, Repo}

  import Ecto.Query

  @weak_threshold 80.0

  def generate(user_role_id, test_schedule_id) do
    schedule = Assessments.get_test_schedule_with_course!(test_schedule_id)
    readiness = Assessments.latest_readiness(user_role_id, test_schedule_id)
    course = Courses.get_course_with_chapters!(schedule.course_id)
    chapters = course.chapters

    weak_chapters = identify_weak_chapters(readiness, chapters)
    days_until_test = days_until(schedule.test_date)
    study_plan = build_study_plan(weak_chapters, schedule.test_date, days_until_test)

    sections =
      Enum.map(weak_chapters, fn {chapter, score} ->
        wrong_questions = enrich_wrong_questions(user_role_id, chapter.id)
        {total_attempted, total_correct} = chapter_attempt_stats(user_role_id, chapter.id)
        source_materials = chapter_source_materials(chapter.id)

        %{
          "chapter_id" => chapter.id,
          "chapter_name" => chapter.name,
          "score" => score,
          "priority" => priority_label(score),
          "total_attempted" => total_attempted,
          "total_correct" => total_correct,
          "source_materials" => source_materials,
          "review_topics" => build_review_topics(chapter, wrong_questions, score),
          "wrong_questions" => wrong_questions,
          "reviewed" => false
        }
      end)

    content = %{
      "title" => "Study Guide: #{schedule.name}",
      "generated_for" => schedule.course.name,
      "course_id" => schedule.course_id,
      "test_date" => Date.to_string(schedule.test_date),
      "days_until_test" => days_until_test,
      "aggregate_score" => (readiness && readiness.aggregate_score) || 0,
      "study_plan" => study_plan,
      "sections" => sections,
      "progress" => %{
        "sections_reviewed" => 0,
        "total_sections" => length(sections),
        "plan_days_completed" => 0,
        "total_plan_days" => length(study_plan)
      }
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
    |> Enum.filter(fn {_ch, score} -> score < @weak_threshold end)
    |> Enum.sort_by(fn {_ch, score} -> score end)
  end

  @doc false
  def priority_label(score) when score < 30, do: "Critical"
  def priority_label(score) when score < 50, do: "High"
  def priority_label(score) when score < 70, do: "Medium"
  def priority_label(_), do: "Low"

  # --- Private helpers ---

  defp days_until(test_date) do
    Date.diff(test_date, Date.utc_today()) |> max(0)
  end

  defp build_study_plan(weak_chapters, test_date, days_until_test) do
    if days_until_test == 0 or weak_chapters == [] do
      []
    else
      # Reserve last day for review
      study_days = max(days_until_test - 1, 1)
      today = Date.utc_today()

      # Sort by priority (lowest score first) and distribute across days
      # Critical/High chapters get more days, Low chapters share days
      {critical_high, medium_low} =
        Enum.split_with(weak_chapters, fn {_ch, score} -> score < 50 end)

      # Assign chapters to days, critical first
      all_ordered = critical_high ++ medium_low
      assignments = distribute_chapters(all_ordered, study_days)

      Enum.with_index(assignments, fn {chapter_ids, focus}, idx ->
        date = Date.add(today, idx + 1)

        %{
          "day" => idx + 1,
          "date" => Date.to_string(date),
          "chapter_ids" => chapter_ids,
          "focus" => focus,
          "completed" => false
        }
      end)
      |> maybe_add_review_day(test_date, days_until_test)
    end
  end

  defp distribute_chapters(chapters, study_days) do
    if chapters == [] do
      []
    else
      # Each critical/high chapter gets its own day if possible
      # Medium/low chapters share days
      total = length(chapters)

      if total <= study_days do
        # Each chapter gets at least one day
        Enum.map(chapters, fn {ch, score} ->
          focus =
            case priority_label(score) do
              "Critical" -> "Deep review - needs significant work"
              "High" -> "Focused study - important gaps"
              "Medium" -> "Moderate review - some gaps"
              "Low" -> "Light review - almost there"
            end

          {[ch.id], focus}
        end)
      else
        # More chapters than days - group them
        chunks = Enum.chunk_every(chapters, ceil(total / study_days))

        Enum.map(chunks, fn chunk ->
          ids = Enum.map(chunk, fn {ch, _} -> ch.id end)
          worst = chunk |> Enum.map(fn {_, s} -> s end) |> Enum.min()
          focus = "Combined review (#{length(chunk)} chapters, lowest: #{round(worst)}%)"
          {ids, focus}
        end)
      end
    end
  end

  defp maybe_add_review_day(plan, test_date, days_until_test) when days_until_test > 1 do
    plan ++
      [
        %{
          "day" => days_until_test,
          "date" => Date.to_string(Date.add(test_date, -1)),
          "chapter_ids" => [],
          "focus" => "Final review - revisit all weak areas",
          "completed" => false
        }
      ]
  end

  defp maybe_add_review_day(plan, _test_date, _days), do: plan

  defp enrich_wrong_questions(user_role_id, chapter_id) do
    wrong = Questions.list_wrong_questions_for_chapter(user_role_id, chapter_id)

    Enum.map(wrong, fn q ->
      attempt_count = count_question_attempts(user_role_id, q.id)

      %{
        "id" => q.id,
        "content" => q.content,
        "answer" => q.answer,
        "question_type" => to_string(q.question_type),
        "difficulty" => to_string(q.difficulty || "medium"),
        "attempt_count" => attempt_count,
        "source_page" => q.source_page
      }
    end)
  end

  defp count_question_attempts(user_role_id, question_id) do
    from(qa in FunSheep.Questions.QuestionAttempt,
      where: qa.user_role_id == ^user_role_id and qa.question_id == ^question_id,
      select: count(qa.id)
    )
    |> Repo.one()
  end

  defp chapter_attempt_stats(user_role_id, chapter_id) do
    total = Questions.count_total_attempts(user_role_id, chapter_id)
    correct = Questions.count_correct_attempts(user_role_id, chapter_id)
    {total, correct}
  end

  defp chapter_source_materials(chapter_id) do
    from(q in FunSheep.Questions.Question,
      where: q.chapter_id == ^chapter_id and not is_nil(q.source_material_id),
      join: m in assoc(q, :source_material),
      distinct: m.id,
      select: %{id: m.id, file_name: m.file_name}
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      %{"id" => m.id, "file_name" => m.file_name}
    end)
  end

  defp build_review_topics(_chapter, wrong_questions, score) do
    topics = []

    # Add priority-based guidance
    topics =
      case priority_label(score) do
        "Critical" ->
          topics ++
            [
              "Start from basics - this chapter needs the most attention",
              "Re-read the chapter material before attempting practice questions"
            ]

        "High" ->
          topics ++
            [
              "Focus on the #{length(wrong_questions)} questions you got wrong",
              "Review key concepts before practicing"
            ]

        "Medium" ->
          topics ++ ["Target your specific weak spots in this chapter"]

        "Low" ->
          topics ++ ["Quick review - you're close to mastery"]
      end

    # Add question-type-specific tips
    types =
      wrong_questions
      |> Enum.map(& &1["question_type"])
      |> Enum.frequencies()

    if Map.get(types, "multiple_choice", 0) > 2 do
      topics = topics ++ ["Practice eliminating wrong options in multiple choice"]
      topics
    else
      topics
    end
  end
end
