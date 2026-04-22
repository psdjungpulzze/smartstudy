defmodule FunSheep.Assessments.ReadinessCalculator do
  @moduledoc """
  Calculates test readiness scores.

  North Star I-9 (per-skill mastery) + I-10 (weakest-skill-weighted
  aggregate):

    * `chapter_scores` — preserved for backward compatibility (correct/total
      per chapter).
    * `skill_scores` — per-section `%{correct, total, score, status}` where
      status ∈ :insufficient_data | :probing | :weak | :mastered.
    * `aggregate_score` — weakest-N-average of skill scores (lowest 3 by
      default) when any skill has data; otherwise a chapter-based fallback
      so legacy callers keep working.
  """

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Assessments.Mastery

  @weakest_n 3

  def calculate(user_role_id, test_schedule) do
    chapter_ids = get_in(test_schedule.scope, ["chapter_ids"]) || []

    chapter_scores =
      Enum.into(chapter_ids, %{}, fn ch_id ->
        {ch_id, calculate_chapter_score(user_role_id, ch_id)}
      end)

    skill_scores = calculate_skill_scores(user_role_id, chapter_ids)
    aggregate = aggregate_score(skill_scores, chapter_scores)

    %{
      chapter_scores: chapter_scores,
      topic_scores: %{},
      skill_scores: skill_scores,
      aggregate_score: Float.round(aggregate, 1)
    }
  end

  @doc """
  True iff every in-scope skill has reached mastery. Used by Study Path
  to honor I-8 (no 80% stopping point).
  """
  def all_skills_mastered?(%{skill_scores: skill_scores}) when is_map(skill_scores) do
    skill_scores != %{} and
      Enum.all?(skill_scores, fn {_id, data} -> skill_status(data) == :mastered end)
  end

  def all_skills_mastered?(_), do: false

  @doc """
  True iff the student has completed the diagnostic for every in-scope
  skill — i.e., every section has at least one recorded attempt. This is
  the correct "Assessment done" signal for Study Path: a readiness record
  exists for any student who has answered one question, so we must actually
  check coverage instead of "has_readiness". When a course has no sections
  yet (skill_scores empty), fall back to the chapter-level heuristic of
  every chapter having attempted questions.
  """
  def assessment_complete?(nil), do: false

  def assessment_complete?(%{skill_scores: skill_scores} = readiness)
      when is_map(skill_scores) and map_size(skill_scores) > 0 do
    Enum.all?(skill_scores, fn {_id, data} -> skill_total(data) > 0 end) or
      chapters_all_attempted?(readiness)
  end

  def assessment_complete?(%{chapter_scores: cs} = readiness)
      when is_map(cs) and map_size(cs) > 0 do
    chapters_all_attempted?(readiness)
  end

  def assessment_complete?(_), do: false

  # When every chapter has ≥1 attempt we can treat the diagnostic as
  # complete even if section-level data is sparse. ReadinessScore only
  # exposes chapter % not counts, so we derive "had any attempts" from
  # nonzero score ∨ skill data against that chapter.
  defp chapters_all_attempted?(%{chapter_scores: cs, skill_scores: ss})
       when is_map(cs) and map_size(cs) > 0 do
    attempted_chapter_ids =
      ss
      |> Map.values()
      |> Enum.filter(&(skill_total(&1) > 0))
      |> Enum.map(fn data -> Map.get(data, :chapter_id) || Map.get(data, "chapter_id") end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.all?(cs, fn {chapter_id, score} ->
      score > 0 or MapSet.member?(attempted_chapter_ids, chapter_id)
    end)
  end

  defp chapters_all_attempted?(_), do: false

  defp skill_total(%{total: t}) when is_integer(t), do: t
  defp skill_total(%{"total" => t}) when is_integer(t), do: t
  defp skill_total(_), do: 0

  @doc "Section IDs currently below mastery in the readiness snapshot."
  def unmastered_skills(%{skill_scores: skill_scores}) when is_map(skill_scores) do
    skill_scores
    |> Enum.reject(fn {_id, data} -> skill_status(data) == :mastered end)
    |> Enum.map(fn {id, _} -> id end)
  end

  def unmastered_skills(_), do: []

  defp calculate_chapter_score(user_role_id, chapter_id) do
    correct = Questions.count_correct_attempts(user_role_id, chapter_id)
    total = Questions.count_total_attempts(user_role_id, chapter_id)
    if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0
  end

  defp calculate_skill_scores(_user_role_id, []), do: %{}

  defp calculate_skill_scores(user_role_id, chapter_ids) do
    sections = Courses.list_sections_by_chapters(chapter_ids)

    Enum.into(sections, %{}, fn section ->
      attempts = Questions.list_section_attempts(user_role_id, section.id)
      correct = Enum.count(attempts, & &1.is_correct)
      total = length(attempts)
      score = if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0
      status = Mastery.status(attempts)

      {section.id,
       %{
         correct: correct,
         total: total,
         score: score,
         status: status,
         chapter_id: section.chapter_id
       }}
    end)
  end

  defp aggregate_score(skill_scores, chapter_scores) do
    scored_skills =
      skill_scores |> Map.values() |> Enum.filter(&(&1.total > 0))

    cond do
      scored_skills != [] ->
        if Enum.all?(scored_skills, &(&1.status == :mastered)) and
             map_size(skill_scores) == Enum.count(scored_skills, &(&1.status == :mastered)) do
          100.0
        else
          weakest_n_average(scored_skills)
        end

      chapter_scores == %{} ->
        0.0

      true ->
        scores = Map.values(chapter_scores)
        Enum.sum(scores) / length(scores)
    end
  end

  defp weakest_n_average(skills) do
    sorted = skills |> Enum.map(& &1.score) |> Enum.sort()
    n = min(@weakest_n, length(sorted))
    bottom = Enum.take(sorted, n)
    Enum.sum(bottom) / n
  end

  defp skill_status(%{status: status}) when is_atom(status), do: status
  defp skill_status(%{"status" => status}) when is_binary(status), do: String.to_atom(status)
  defp skill_status(_), do: :insufficient_data
end
