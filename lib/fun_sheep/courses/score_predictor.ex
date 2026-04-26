defmodule FunSheep.Courses.ScorePredictor do
  @moduledoc """
  Generic score predictor for any standardized test course.

  Reads domain weights from `course.metadata["score_predictor_weights"]` and
  the score range from `course.metadata["score_range"]` (defaults to [0, 100]).

  ## Usage

      mastery = %{"algebra" => 0.8, "advanced_math" => 0.6}
      FunSheep.Courses.ScorePredictor.predict_score(course, mastery)
      #=> 680  (for a 200–800 course with appropriate weights)

  Domain keys must be lowercase underscored versions of chapter names.
  Use `FunSheep.SAT.ScorePredictor.domain_key/1` for conversion.
  """

  alias FunSheep.Courses.Course

  @doc """
  Predict a section score from a domain mastery map.

  `mastery_map` maps domain keys (lowercase underscored chapter names) to
  float mastery levels (0.0–1.0).

  Returns an integer score within the course's `score_range`, or `nil` if
  there is insufficient data (no covered domains, missing weights).
  """
  @spec predict_score(Course.t(), %{String.t() => float()}) :: integer() | nil
  def predict_score(%Course{metadata: metadata} = _course, mastery_map) when is_map(metadata) do
    weights = Map.get(metadata, "score_predictor_weights") || %{}
    score_range = Map.get(metadata, "score_range") || [0, 100]

    predict(mastery_map, weights, score_range)
  end

  def predict_score(_course, _mastery_map), do: nil

  # --- Private --------------------------------------------------------------

  defp predict(mastery_map, weights, [min_score, max_score])
       when map_size(weights) > 0 do
    covered = Enum.filter(weights, fn {k, _} -> Map.has_key?(mastery_map, k) end)

    if covered == [] do
      nil
    else
      do_predict(mastery_map, weights, min_score, max_score)
    end
  end

  defp predict(_mastery_map, _weights, _range), do: nil

  defp do_predict(mastery_map, weights, min_score, max_score) do
    {weighted_sum, weight_sum} =
      Enum.reduce(weights, {0.0, 0.0}, fn {domain, weight}, {ws, wt} ->
        case Map.get(mastery_map, domain) do
          nil -> {ws, wt}
          mastery -> {ws + mastery * weight, wt + weight}
        end
      end)

    if weight_sum == 0.0 do
      nil
    else
      weighted_avg = weighted_sum / weight_sum
      round(min_score + weighted_avg * (max_score - min_score))
    end
  end
end
