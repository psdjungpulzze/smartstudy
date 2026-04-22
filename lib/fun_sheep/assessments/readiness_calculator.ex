defmodule FunSheep.Assessments.ReadinessCalculator do
  @moduledoc """
  Calculates test readiness scores from question attempts.

  Aligned with North Star invariants I-9 (per-skill mastery) and I-10
  (aggregate reflects the weakest in-scope skills, not a naive average).

  Layering:
    * `chapter_scores` — preserved for backward compatibility with existing
      readers (kept as simple `correct/total` per chapter).
    * `skill_scores` — per-section map of `%{correct, total, score, status}`
      where `status` ∈ `:insufficient_data | :probing | :weak | :mastered`.
    * `aggregate_score` — weakest-N-average of skill scores (lowest 3 by
      default) when any skill has data; otherwise a chapter-based fallback
      so legacy callers keep working.
  """

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Assessments.Mastery

  # How many of the weakest skills the aggregate focuses on. Small N
  # emphasizes weakness per I-10.
  @weakest_n 3

  @doc """
  Calculates readiness scores for a user against a test schedule's scope.

  Returns a map with:
    * `:chapter_scores` — `%{chapter_id => score_pct}`
    * `:topic_scores` — placeholder for legacy callers
    * `:skill_scores` — `%{section_id => %{correct, total, score, status}}`
    * `:aggregate_score` — weakest-N-average of skill scores (0.0–100.0)
  """
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
  Returns true iff every in-scope skill for the given readiness snapshot
  has reached mastery. Used by the Study Path to honor I-8 (no 80%
  stopping point; keep drilling until 100%).
  """
  def all_skills_mastered?(%{skill_scores: skill_scores}) when is_map(skill_scores) do
    skill_scores != %{} and
      Enum.all?(skill_scores, fn {_id, data} -> skill_status(data) == :mastered end)
  end

  def all_skills_mastered?(_), do: false

  @doc """
  Lists the skills (by section_id) currently below mastery in a readiness
  snapshot. The Study Path uses this to decide whether the "keep drilling"
  CTA stays active above 80% readiness.
  """
  def unmastered_skills(%{skill_scores: skill_scores}) when is_map(skill_scores) do
    skill_scores
    |> Enum.reject(fn {_id, data} -> skill_status(data) == :mastered end)
    |> Enum.map(fn {id, _} -> id end)
  end

  def unmastered_skills(_), do: []

  # --- Private ---

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
         status: status
       }}
    end)
  end

  # Weakest-N-average when skill data exists; otherwise fall back to the
  # legacy chapter-based arithmetic mean so old callers (and courses that
  # haven't been classified into sections yet) still produce a number.
  defp aggregate_score(skill_scores, chapter_scores) do
    scored_skills =
      skill_scores
      |> Map.values()
      |> Enum.filter(&(&1.total > 0))

    cond do
      scored_skills != [] ->
        # All skills mastered ⇒ aggregate = 100 (I-8, I-10). Otherwise
        # focus on the weakest few so low-scoring outliers can't be hidden
        # behind strong ones.
        if Enum.all?(scored_skills, &(&1.status == :mastered)) and
             map_size(skill_scores) ==
               Enum.count(scored_skills, &(&1.status == :mastered)) do
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

  defp skill_status(%{"status" => status}) when is_binary(status) do
    String.to_atom(status)
  end

  defp skill_status(_), do: :insufficient_data
end
