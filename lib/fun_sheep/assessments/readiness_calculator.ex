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

      {section.id, %{correct: correct, total: total, score: score, status: status}}
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
