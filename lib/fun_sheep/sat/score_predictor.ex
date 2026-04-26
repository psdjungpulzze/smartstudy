defmodule FunSheep.SAT.ScorePredictor do
  @moduledoc """
  SAT-specific score predictor.

  **Deprecated** — new code should use `FunSheep.Courses.ScorePredictor` with
  domain weights stored in `course.metadata["score_predictor_weights"]`.

  This module is kept for backward compatibility (existing callers using
  `predict_math_score/1` and `predict_rw_score/1` continue to work) and
  delegates to the generic predictor using hardcoded SAT weights as a fallback
  when a Course struct is not available.

  Domain weights sourced from College Board's official test specification:
  - Math: Algebra 35%, Advanced Math 35%, PSDA 15%, Geometry/Trig 15%.
  - RW: Craft & Structure 28%, Information & Ideas 26%, Expression 20%,
        Standard English Conventions 26%.

  Domain key convention — lowercase underscored chapter name:
    - "Algebra"                         → "algebra"
    - "Advanced Math"                   → "advanced_math"
    - "Problem-Solving & Data Analysis" → "problem_solving_data_analysis"
    - "Geometry & Trigonometry"         → "geometry_trigonometry"
    - "Craft & Structure"               → "craft_and_structure"
    - "Information & Ideas"             → "information_and_ideas"
    - "Expression of Ideas"             → "expression_of_ideas"
    - "Standard English Conventions"    → "standard_english_conventions"
  """

  @rw_weights %{
    "craft_and_structure" => 0.28,
    "information_and_ideas" => 0.26,
    "expression_of_ideas" => 0.20,
    "standard_english_conventions" => 0.26
  }

  @math_weights %{
    "algebra" => 0.35,
    "advanced_math" => 0.35,
    "problem_solving_data_analysis" => 0.15,
    "geometry_trigonometry" => 0.15
  }

  @sat_score_range [200, 800]

  @doc """
  Predict the SAT Math section score (200–800) from a chapter mastery map.

  Delegates to `FunSheep.Courses.ScorePredictor` using the hardcoded SAT Math
  weights. New callers should use `FunSheep.Courses.ScorePredictor.predict_score/2`
  with a Course struct that has weights in its metadata.
  """
  @spec predict_math_score(%{String.t() => float()}) :: integer() | nil
  def predict_math_score(mastery_map) do
    predict_with_weights(mastery_map, @math_weights, @sat_score_range)
  end

  @doc """
  Predict the SAT Reading & Writing section score (200–800) from a chapter
  mastery map.

  Delegates to `FunSheep.Courses.ScorePredictor` using the hardcoded SAT RW
  weights. New callers should use `FunSheep.Courses.ScorePredictor.predict_score/2`
  with a Course struct that has weights in its metadata.
  """
  @spec predict_rw_score(%{String.t() => float()}) :: integer() | nil
  def predict_rw_score(mastery_map) do
    predict_with_weights(mastery_map, @rw_weights, @sat_score_range)
  end

  @doc """
  Returns the domain weight map for a given catalog_subject.
  Useful for building the readiness heatmap.
  """
  @spec domain_weights(String.t()) :: %{String.t() => float()}
  def domain_weights("mathematics"), do: @math_weights
  def domain_weights("reading_writing"), do: @rw_weights
  def domain_weights(_), do: %{}

  @doc """
  Normalises a chapter name to the domain key used in mastery maps and
  weight tables.

  ## Examples

      iex> FunSheep.SAT.ScorePredictor.domain_key("Algebra")
      "algebra"

      iex> FunSheep.SAT.ScorePredictor.domain_key("Problem-Solving & Data Analysis")
      "problem_solving_data_analysis"

  """
  @spec domain_key(String.t()) :: String.t()
  def domain_key(chapter_name) do
    chapter_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  # ── Private ───────────────────────────────────────────────────────────────

  # Inline the weighted prediction so we don't need to construct a Course struct.
  # The generic `FunSheep.Courses.ScorePredictor.predict_score/2` expects a
  # Course struct with metadata; for the SAT legacy path we replicate the
  # arithmetic directly to avoid a circular dependency at compile time.
  defp predict_with_weights(mastery_map, weights, [min_score, max_score]) do
    covered = Enum.filter(weights, fn {k, _} -> Map.has_key?(mastery_map, k) end)

    if covered == [] do
      nil
    else
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
end
