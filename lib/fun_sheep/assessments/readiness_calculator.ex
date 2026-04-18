defmodule FunSheep.Assessments.ReadinessCalculator do
  @moduledoc """
  Calculates test readiness scores from question attempts.

  Computes per-chapter, per-topic, and aggregate scores.
  Weights recent attempts more heavily (future enhancement).
  """

  alias FunSheep.Questions

  @doc """
  Calculates readiness scores for a user against a test schedule's scope.

  Returns a map with:
  - `:chapter_scores` - map of chapter_id => score (0-100)
  - `:topic_scores` - placeholder for section-level scores
  - `:aggregate_score` - average of chapter scores (0-100)
  """
  def calculate(user_role_id, test_schedule) do
    chapter_ids = get_in(test_schedule.scope, ["chapter_ids"]) || []

    chapter_scores =
      Enum.into(chapter_ids, %{}, fn ch_id ->
        {ch_id, calculate_chapter_score(user_role_id, ch_id)}
      end)

    aggregate =
      if map_size(chapter_scores) > 0 do
        scores = Map.values(chapter_scores)
        Enum.sum(scores) / length(scores)
      else
        0.0
      end

    %{
      chapter_scores: chapter_scores,
      topic_scores: %{},
      aggregate_score: Float.round(aggregate, 1)
    }
  end

  defp calculate_chapter_score(user_role_id, chapter_id) do
    correct = Questions.count_correct_attempts(user_role_id, chapter_id)
    total = Questions.count_total_attempts(user_role_id, chapter_id)

    if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0
  end
end
