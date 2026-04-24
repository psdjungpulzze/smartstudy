defmodule FunSheep.Questions.ScoredFreeformGrader do
  @moduledoc """
  AI-powered rubric grader for `short_answer` and `free_response` question types.

  Returns a 0–10 score with per-criterion breakdown, feedback, and an optional
  improvement hint. Uses Claude Sonnet at low temperature for precise, consistent
  academic grading.

  ## Fallback chain

    1. Scored grader (Sonnet) — full rubric result
    2. FreeformGrader (Haiku binary) — synthesized score (0 or 10)
    3. Grading.correct? (exact match) — synthesized score (0 or 10)

  `is_correct` is ALWAYS computed server-side as `score >= 7`, regardless of any
  `is_correct` flag the AI may return.
  """

  alias FunSheep.Questions.{FreeformGrader, Grading}

  require Logger

  @system_prompt """
  You are a precise academic grader for a high-stakes test preparation platform.

  Your task: grade a student's freeform answer against a reference answer using a 10-point rubric.

  Scoring rubric:
    Factual Accuracy  (0–4): Is the core claim correct? Penalize misconceptions and inverted causality.
    Completeness      (0–3): Are all required components present? Penalize missing mechanisms or steps.
    Clarity & Logic   (0–2): Is the explanation coherent and does it show understanding (not just recall)?
    Terminology       (0–1): Are domain terms used correctly?

  Grading philosophy:
    - Be generous with valid paraphrasing and scientific equivalents.
    - Be strict about factual errors, especially inverted or contradictory claims.
    - A student who partially understands should receive partial credit, not zero.
    - The improvement_hint must be specific and actionable.
    - Do not fabricate content. If the reference answer is insufficient to grade, say so in the feedback.

  Output a single JSON object. No markdown, no prose outside the JSON.
  Schema: {"score": int, "max_score": 10, "criteria": [{"name": str, "earned": int, "max": int, "comment": str}], "feedback": "...", "improvement_hint": "...", "is_correct": bool}
  """

  @llm_opts %{
    model: "claude-sonnet-4-6",
    max_tokens: 512,
    temperature: 0.1,
    source: "scored_freeform_grader"
  }

  @doc """
  Grades a freeform student answer using a 10-point AI rubric.

  Returns `{:ok, result}` where result is:

      %{
        score: 0..10,
        max_score: 10,
        is_correct: boolean(),          # always score >= 7, not from AI
        feedback: String.t(),
        improvement_hint: String.t() | nil,
        criteria: list(),
        grader_path: :scored_ai | :binary_ai | :exact_match
      }

  Falls back through the chain on any failure. Never returns `{:error, _}`.
  """
  @spec grade(map() | struct(), String.t()) ::
          {:ok,
           %{
             score: non_neg_integer(),
             max_score: 10,
             is_correct: boolean(),
             feedback: String.t(),
             improvement_hint: String.t() | nil,
             criteria: list(),
             grader_path: :scored_ai | :binary_ai | :exact_match
           }}
  def grade(_question, answer) when is_binary(answer) and byte_size(answer) == 0 do
    {:ok,
     %{
       score: 0,
       max_score: 10,
       is_correct: false,
       feedback: "No answer provided.",
       improvement_hint: nil,
       criteria: [],
       grader_path: :scored_ai
     }}
  end

  def grade(question, student_answer) do
    reference_answer = Map.get(question, :answer) || Map.get(question, "answer") || ""

    if reference_answer == "" do
      fallback_to_binary(question, student_answer)
    else
      prompt = build_prompt(question, student_answer, reference_answer)

      case ai_client().call(@system_prompt, prompt, @llm_opts) do
        {:ok, response_text} ->
          case parse_response(response_text) do
            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              Logger.warning(
                "[ScoredFreeformGrader] Failed to parse AI response (#{inspect(reason)}), falling back to binary grader"
              )

              fallback_to_binary(question, student_answer)
          end

        {:error, reason} ->
          Logger.error(
            "[ScoredFreeformGrader] AI call failed (#{inspect(reason)}), falling back to binary grader"
          )

          fallback_to_binary(question, student_answer)
      end
    end
  end

  # ── Fallback chain ──

  defp fallback_to_binary(question, student_answer) do
    case FreeformGrader.grade(question, student_answer) do
      {:ok, %{correct: is_correct}} ->
        score = if is_correct, do: 10, else: 0

        {:ok,
         %{
           score: score,
           max_score: 10,
           is_correct: is_correct,
           feedback: nil,
           improvement_hint: nil,
           criteria: [],
           grader_path: :binary_ai
         }}

      _ ->
        is_correct = Grading.correct?(question, student_answer)
        score = if is_correct, do: 10, else: 0

        {:ok,
         %{
           score: score,
           max_score: 10,
           is_correct: is_correct,
           feedback: nil,
           improvement_hint: nil,
           criteria: [],
           grader_path: :exact_match
         }}
    end
  end

  # ── Prompt builder ──

  defp build_prompt(question, student_answer, reference_answer) do
    question_content = Map.get(question, :content) || Map.get(question, "content") || ""

    """
    Question: #{question_content}

    Reference answer: #{reference_answer}

    Student's answer: #{student_answer}
    """
  end

  # ── Response parser ──

  defp parse_response(text) do
    cleaned =
      text
      |> String.trim()
      |> strip_markdown_code_fence()

    case Jason.decode(cleaned) do
      {:ok, parsed} ->
        build_result(parsed)

      {:error, reason} ->
        Logger.warning(
          "[ScoredFreeformGrader] Failed to parse AI response as JSON: #{inspect(reason)}"
        )

        {:error, :json_parse_failed}
    end
  end

  defp build_result(%{"score" => raw_score} = parsed) when is_number(raw_score) do
    score =
      raw_score
      |> round()
      |> clamp(0, 10)

    is_correct = score >= 7

    feedback =
      case Map.get(parsed, "feedback") do
        val when is_binary(val) and val != "" -> val
        _ -> nil
      end

    improvement_hint =
      case Map.get(parsed, "improvement_hint") do
        val when is_binary(val) and val != "" -> val
        _ -> nil
      end

    criteria = Map.get(parsed, "criteria") || []

    {:ok,
     %{
       score: score,
       max_score: 10,
       is_correct: is_correct,
       feedback: feedback,
       improvement_hint: improvement_hint,
       criteria: criteria,
       grader_path: :scored_ai
     }}
  end

  defp build_result(other) do
    Logger.warning("[ScoredFreeformGrader] Unexpected JSON shape: #{inspect(other)}")
    {:error, :unexpected_shape}
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp strip_markdown_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
