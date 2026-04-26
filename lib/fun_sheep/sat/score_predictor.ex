defmodule FunSheep.SAT.ScorePredictor do
  @moduledoc """
  Predicts SAT section scores from domain mastery levels.

  Domain mastery is a float 0.0–1.0 representing the fraction of questions
  answered correctly for a given domain (chapter). Returns integer scores on
  the 200–800 scale used by each SAT section.

  ## Usage

      mastery = %{
        "algebra" => 0.8,
        "advanced_math" => 0.6,
        "problem_solving_data_analysis" => 0.7,
        "geometry_trigonometry" => 0.5
      }

      FunSheep.SAT.ScorePredictor.predict_math_score(mastery)
      #=> 660

  Domain keys must be lowercase underscored versions of chapter names:
    - "Algebra"                        → "algebra"
    - "Advanced Math"                  → "advanced_math"
    - "Problem-Solving & Data Analysis" → "problem_solving_data_analysis"
    - "Geometry & Trigonometry"        → "geometry_trigonometry"
    - "Craft & Structure"              → "craft_and_structure"
    - "Information & Ideas"            → "information_and_ideas"
    - "Expression of Ideas"            → "expression_of_ideas"
    - "Standard English Conventions"   → "standard_english_conventions"
  """

  # Domain weights sourced from College Board's official test specification.
  # Math: Algebra 35%, Advanced Math 35%, PSDA 15%, Geometry/Trig 15%.
  # RW: Craft & Structure 28%, Information & Ideas 26%, Expression 20%,
  #     Standard English Conventions 26%.
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

  @doc """
  Predict the SAT Math section score (200–800) from a chapter mastery map.

  `mastery_map` keys are domain names (lowercase underscored).
  Returns nil if the map contains no covered domains.
  """
  @spec predict_math_score(%{String.t() => float()}) :: integer() | nil
  def predict_math_score(mastery_map) do
    predict_section_score(mastery_map, @math_weights)
  end

  @doc """
  Predict the SAT Reading & Writing section score (200–800) from a chapter
  mastery map.

  `mastery_map` keys are domain names (lowercase underscored).
  Returns nil if the map contains no covered domains.
  """
  @spec predict_rw_score(%{String.t() => float()}) :: integer() | nil
  def predict_rw_score(mastery_map) do
    predict_section_score(mastery_map, @rw_weights)
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
  weight tables. Used when computing mastery from raw chapter names.

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

  defp predict_section_score(mastery_map, weights) do
    covered_domains =
      Enum.filter(weights, fn {domain, _weight} -> Map.has_key?(mastery_map, domain) end)

    if covered_domains == [] do
      nil
    else
      do_predict(mastery_map, weights)
    end
  end

  defp do_predict(mastery_map, weights) do
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
      round(200 + weighted_avg * 600)
    end
  end
end
