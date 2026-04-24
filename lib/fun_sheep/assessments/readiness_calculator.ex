defmodule FunSheep.Assessments.ReadinessCalculator do
  @moduledoc """
  Calculates test readiness scores.

  North Star I-9 (per-skill mastery) + I-10 (weakest-skill-weighted
  aggregate):

    * `chapter_scores` — preserved for backward compatibility (correct/total
      per chapter).
    * `skill_scores` — per-section `%{correct, total, score, status}` keyed
      by section ID. Only includes sections that have ≥1 student-visible
      question (practicable sections). Sections with 0 questions are tracked
      separately in `empty_section_ids` so they never block 100%.
    * `aggregate_score` — weakest-N-average of skills with ≥ MIN_SIGNAL
      attempts. Skills with fewer attempts are "still probing" and do not
      drag the aggregate down when a student first starts a topic.
    * `coverage_pct` — (practicable sections / total in-scope sections) × 100.
    * `full_test_readiness` — aggregate_score × (coverage_pct / 100). A
      conservative estimate of true preparedness when some topics lack
      questions.
  """

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Assessments.Mastery

  @weakest_n 3
  # Minimum attempts before a skill enters the weakest-N pool. Prevents a
  # student's aggregate from dropping the moment they start a fresh topic.
  @min_signal_attempts 3

  def calculate(user_role_id, test_schedule) do
    chapter_ids = get_in(test_schedule.scope, ["chapter_ids"]) || []

    chapter_scores =
      Enum.into(chapter_ids, %{}, fn ch_id ->
        {ch_id, calculate_chapter_score(user_role_id, ch_id)}
      end)

    {skill_scores, empty_section_ids, coverage_pct} =
      calculate_skill_scores(user_role_id, chapter_ids)

    aggregate = aggregate_score(skill_scores, chapter_scores)

    full_test_readiness = Float.round(aggregate * coverage_pct / 100.0, 1)

    %{
      chapter_scores: chapter_scores,
      topic_scores: %{},
      skill_scores: skill_scores,
      empty_section_ids: empty_section_ids,
      coverage_pct: Float.round(coverage_pct, 1),
      aggregate_score: Float.round(aggregate, 1),
      full_test_readiness: full_test_readiness
    }
  end

  @doc """
  True iff every in-scope skill has reached mastery. Used by Study Path
  to honor I-8 (no 80% stopping point).
  """
  def all_skills_mastered?(%{skill_scores: skill_scores}) when is_map(skill_scores) do
    # skill_scores only contains practicable sections (those with questions),
    # so this can legitimately reach true when all available content is mastered.
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

  # Number of difficulty levels a section must have questions at to count
  # as "fully covered". 3 = easy + medium + hard.
  @difficulty_levels 3

  # Returns {skill_scores, empty_section_ids, coverage_pct}.
  # skill_scores only covers practicable sections (≥1 passed question).
  # empty_section_ids lists sections the student cannot practice yet.
  # coverage_pct is weighted by per-section difficulty supply:
  #   - 3 levels present → contributes 1.0 (full coverage)
  #   - 2 levels → 0.67
  #   - 1 level  → 0.33
  #   - 0 levels → 0.0 (empty)
  # This ensures a section with only easy questions cannot claim full
  # coverage — a student needing medium/hard content would get stuck.
  defp calculate_skill_scores(_user_role_id, []), do: {%{}, [], 100.0}

  defp calculate_skill_scores(user_role_id, chapter_ids) do
    all_sections = Courses.list_sections_by_chapters(chapter_ids)
    total_count = length(all_sections)

    section_ids = Enum.map(all_sections, & &1.id)
    difficulty_coverage = Questions.section_difficulty_counts(section_ids)

    {practicable, empty} =
      Enum.split_with(all_sections, &Map.has_key?(difficulty_coverage, &1.id))

    skill_scores =
      Enum.into(practicable, %{}, fn section ->
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

    empty_section_ids = Enum.map(empty, & &1.id)

    coverage_pct =
      if total_count == 0 do
        100.0
      else
        # Weight each section by how many difficulty levels it has supply for.
        # A section with only easy questions is 1/3 covered, not fully covered.
        weighted_sum =
          Enum.sum(
            Enum.map(all_sections, fn s ->
              levels = Map.get(difficulty_coverage, s.id, MapSet.new()) |> MapSet.size()
              levels / @difficulty_levels
            end)
          )

        weighted_sum / total_count * 100.0
      end

    {skill_scores, empty_section_ids, coverage_pct}
  end

  # Skills with fewer than @min_signal_attempts do not enter the weakest-N
  # pool — they are still being "probed" and shouldn't crash the aggregate.
  defp aggregate_score(skill_scores, chapter_scores) do
    all_attempted = skill_scores |> Map.values() |> Enum.filter(&(&1.total > 0))
    signal_skills = Enum.filter(all_attempted, &(&1.total >= @min_signal_attempts))

    cond do
      all_attempted != [] ->
        all_mastered =
          Enum.all?(skill_scores, fn {_id, data} -> skill_status(data) == :mastered end)

        if all_mastered and map_size(skill_scores) > 0 do
          100.0
        else
          case signal_skills do
            [] ->
              # Every attempted skill is still in the probing window; show a
              # gentle non-zero hint so the bar visibly responds to early work.
              all_attempted
              |> Enum.map(& &1.score)
              |> then(fn scores -> Enum.sum(scores) / length(scores) / 2 end)

            skills ->
              weakest_n_average(skills)
          end
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
