defmodule FunSheep.Questions.EssayGrader do
  @moduledoc """
  AI-powered essay grader using Claude Opus for complex rhetorical judgment.

  Uses the question's associated `essay_rubric_template` for exam-specific
  scoring criteria. Falls back to `ScoredFreeformGrader` (Sonnet, generic
  0–10) on Opus failure, then further to `FreeformGrader` (Haiku binary)
  if Sonnet also fails.

  `is_correct` is ALWAYS server-computed:
    `total_score / max_score >= rubric.mastery_threshold_ratio`

  The AI-returned `is_correct` field (if any) is ignored.
  """

  require Logger

  alias FunSheep.Questions.FreeformGrader
  alias FunSheep.Essays

  @model "claude-opus-4-7"
  @temperature 0.2
  @max_tokens 1024
  @source "essay_grader"

  @type criterion_result :: %{
          name: String.t(),
          earned: integer(),
          max: integer(),
          comment: String.t()
        }

  @type grade_result :: %{
          total_score: integer(),
          max_score: integer(),
          is_correct: boolean(),
          feedback: String.t(),
          strengths: [String.t()],
          improvements: [String.t()],
          criteria: [criterion_result()],
          grader: :essay_opus | :scored_sonnet | :binary_haiku | :exact_match
        }

  @doc """
  Grades an essay against the question's rubric template.

  Returns `{:ok, grade_result()}`.

  ## Fallback chain
  1. Opus with rubric → structured per-criterion scoring
  2. ScoredFreeformGrader (Sonnet, 0–10) — if no rubric or Opus failure
  3. FreeformGrader (Haiku, binary) — if Sonnet also fails

  ## Blank essay
  Returns a zero score immediately without an AI call.
  """
  @spec grade(map() | struct(), String.t()) :: {:ok, grade_result()}
  def grade(question, essay_body) do
    if blank?(essay_body) do
      {:ok, blank_result(question)}
    else
      rubric = load_rubric(question)

      if rubric do
        grade_with_rubric(question, essay_body, rubric)
      else
        grade_fallback_scored(question, essay_body)
      end
    end
  end

  ## Private

  defp blank?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_), do: true

  defp load_rubric(question) do
    # Prefer preloaded association; fall back to a DB lookup by ID.
    case Map.get(question, :essay_rubric_template) do
      %Essays.EssayRubricTemplate{} = rubric ->
        rubric

      _ ->
        rubric_id = Map.get(question, :essay_rubric_template_id)

        if rubric_id do
          Essays.get_rubric_template(rubric_id)
        else
          nil
        end
    end
  end

  defp grade_with_rubric(question, essay_body, rubric) do
    system_prompt = build_system_prompt(rubric)
    user_prompt = build_user_prompt(question, essay_body)
    opts = %{model: @model, temperature: @temperature, max_tokens: @max_tokens, source: @source}

    case ai_client().call(system_prompt, user_prompt, opts) do
      {:ok, response_text} ->
        case parse_response(response_text, rubric) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            Logger.warning(
              "[EssayGrader] Failed to parse Opus response (#{inspect(reason)}), " <>
                "falling back to ScoredFreeformGrader"
            )

            grade_fallback_scored(question, essay_body)
        end

      {:error, reason} ->
        Logger.error(
          "[EssayGrader] Opus call failed (#{inspect(reason)}), " <>
            "falling back to ScoredFreeformGrader"
        )

        grade_fallback_scored(question, essay_body)
    end
  end

  defp grade_fallback_scored(question, essay_body) do
    case freeform_grade(question, essay_body) do
      {:ok, %{correct: correct, feedback: feedback}} ->
        result = %{
          total_score: if(correct, do: 10, else: 5),
          max_score: 10,
          is_correct: correct,
          feedback: feedback || "",
          strengths: [],
          improvements: [],
          criteria: [],
          grader: :scored_sonnet
        }

        {:ok, result}

      _ ->
        grade_fallback_binary(question, essay_body)
    end
  end

  defp grade_fallback_binary(question, essay_body) do
    case FreeformGrader.grade(question, essay_body) do
      {:ok, %{correct: correct, feedback: feedback}} ->
        result = %{
          total_score: if(correct, do: 1, else: 0),
          max_score: 1,
          is_correct: correct,
          feedback: feedback || "",
          strengths: [],
          improvements: [],
          criteria: [],
          grader: :binary_haiku
        }

        {:ok, result}

      _ ->
        {:ok, error_result()}
    end
  end

  # Delegates to ScoredFreeformGrader if available; otherwise falls through to
  # FreeformGrader. We check at runtime with `function_exported?` so the code
  # still compiles even if ScoredFreeformGrader doesn't exist yet.
  defp freeform_grade(question, essay_body) do
    scored_mod = Module.concat(FunSheep.Questions, ScoredFreeformGrader)

    if Code.ensure_loaded?(scored_mod) and function_exported?(scored_mod, :grade, 2) do
      apply(scored_mod, :grade, [question, essay_body])
    else
      FreeformGrader.grade(question, essay_body)
    end
  end

  defp build_system_prompt(rubric) do
    criteria_lines =
      rubric.criteria
      |> normalize_criteria_list()
      |> Enum.map_join("\n", fn c ->
        "  - #{c["name"]} (#{c["max_points"]} pts): #{c["description"]}"
      end)

    """
    You are an expert essay grader. Score the student essay against the rubric below.

    Rubric: #{rubric.name}
    Max score: #{rubric.max_score}

    Criteria:
    #{criteria_lines}

    Respond ONLY with valid JSON matching this exact schema — no prose, no markdown:
    {
      "total_score": <integer 0–#{rubric.max_score}>,
      "max_score": #{rubric.max_score},
      "criteria": [
        {"name": "<criterion name>", "earned": <integer>, "max": <integer>, "comment": "<1-2 sentences>"},
        ...
      ],
      "feedback": "<overall feedback paragraph, 2-4 sentences>",
      "strengths": ["<strength 1>", "<strength 2>"],
      "improvements": ["<improvement 1>", "<improvement 2>"],
      "is_correct": <true|false>
    }

    Be rigorous but fair. Score based solely on the provided rubric criteria.
    Do NOT award points for length alone — evaluate quality and adherence to criteria.
    """
  end

  defp build_user_prompt(question, essay_body) do
    prompt_text =
      Map.get(question, :content) || Map.get(question, "content") || "(no prompt provided)"

    """
    Essay Prompt: #{prompt_text}

    Student Essay:
    #{essay_body}
    """
  end

  defp parse_response(text, rubric) do
    cleaned =
      text
      |> String.trim()
      |> strip_markdown_fence()

    case Jason.decode(cleaned) do
      {:ok, parsed} ->
        build_result(parsed, rubric)

      {:error, reason} ->
        {:error, {:json_parse_failed, reason}}
    end
  end

  defp build_result(parsed, rubric) do
    with {:ok, total_score} <- extract_integer(parsed, "total_score"),
         {:ok, max_score} <- extract_integer(parsed, "max_score") do
      threshold = rubric.mastery_threshold_ratio
      # Always compute is_correct server-side — ignore whatever the AI returned.
      is_correct = max_score > 0 and total_score / max_score >= threshold

      criteria =
        case parsed["criteria"] do
          list when is_list(list) -> Enum.map(list, &normalize_criterion/1)
          _ -> []
        end

      result = %{
        total_score: total_score,
        max_score: max_score,
        is_correct: is_correct,
        feedback: to_string(parsed["feedback"] || ""),
        strengths: normalize_string_list(parsed["strengths"]),
        improvements: normalize_string_list(parsed["improvements"]),
        criteria: criteria,
        grader: :essay_opus
      }

      {:ok, result}
    end
  end

  defp extract_integer(map, key) do
    case Map.get(map, key) do
      v when is_integer(v) -> {:ok, v}
      v when is_float(v) -> {:ok, round(v)}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp normalize_criterion(%{"name" => name, "earned" => earned, "max" => max} = c) do
    %{
      name: to_string(name),
      earned: to_int(earned),
      max: to_int(max),
      comment: to_string(c["comment"] || "")
    }
  end

  defp normalize_criterion(other), do: %{name: inspect(other), earned: 0, max: 0, comment: ""}

  defp normalize_string_list(list) when is_list(list) do
    Enum.map(list, &to_string/1)
  end

  defp normalize_string_list(_), do: []

  defp normalize_criteria_list(criteria) when is_list(criteria), do: criteria

  defp normalize_criteria_list(%{"criteria" => list}) when is_list(list), do: list

  defp normalize_criteria_list(_), do: []

  defp strip_markdown_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\n?/m, "")
    |> String.replace(~r/\n?```$/m, "")
    |> String.trim()
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_float(v), do: round(v)
  defp to_int(_), do: 0

  defp blank_result(question) do
    max_score = rubric_max_score(question)

    %{
      total_score: 0,
      max_score: max_score,
      is_correct: false,
      feedback: "No essay submitted.",
      strengths: [],
      improvements: ["Submit a written response to receive a score."],
      criteria: [],
      grader: :exact_match
    }
  end

  defp error_result do
    %{
      total_score: 0,
      max_score: 1,
      is_correct: false,
      feedback: "Grading service temporarily unavailable. Please try again.",
      strengths: [],
      improvements: [],
      criteria: [],
      grader: :exact_match
    }
  end

  defp rubric_max_score(question) do
    case load_rubric(question) do
      %{max_score: max} when is_integer(max) -> max
      _ -> 10
    end
  end

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
