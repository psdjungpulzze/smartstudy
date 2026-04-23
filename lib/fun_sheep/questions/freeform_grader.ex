defmodule FunSheep.Questions.FreeformGrader do
  @moduledoc """
  AI-powered grader for `short_answer` and `free_response` question types.

  Uses Interactor to evaluate whether a student's answer is semantically
  correct, even when worded differently from the stored reference answer.
  Falls back to exact string match if the AI call fails, so a grading
  result is always returned.
  """

  @behaviour FunSheep.Interactor.AssistantSpec

  alias FunSheep.Interactor.Agents
  alias FunSheep.Questions.Grading

  require Logger

  @assistant_name "funsheep_answer_grader"

  @system_prompt """
  You are a precise answer grader for a student study app. Given a question, a reference answer, and a student's answer, determine if the student's answer is scientifically/factually correct and addresses the core concept — even if worded differently from the reference answer.

  Respond ONLY with valid JSON: {"correct": true, "feedback": null} for correct answers, or {"correct": false, "feedback": "Brief explanation of what was missing or wrong (1-2 sentences)"} for incorrect answers.

  Be generous with scientific equivalents and paraphrasing. Be strict about factual errors or answers that miss the core concept entirely.
  """

  @impl FunSheep.Interactor.AssistantSpec
  def assistant_attrs do
    %{
      name: @assistant_name,
      description: "Grades short-answer and free-response questions semantically",
      system_prompt: @system_prompt,
      llm_provider: "anthropic",
      llm_model: "claude-haiku-4-5-20251001",
      llm_config: %{temperature: 0.1, max_tokens: 256},
      metadata: %{app: "funsheep", role: "grader"}
    }
  end

  @doc """
  Grades a freeform student answer using AI semantic comparison.

  Returns `{:ok, %{correct: boolean(), feedback: String.t() | nil}}`.

  On any Interactor or parsing failure, falls back to exact string match
  and returns `{:ok, %{correct: boolean(), feedback: nil}}`.
  """
  @spec grade(map() | struct(), String.t()) ::
          {:ok, %{correct: boolean(), feedback: String.t() | nil}}
  def grade(question, student_answer) do
    with {:ok, _assistant_id} <- ensure_assistant(),
         prompt <- build_prompt(question, student_answer),
         {:ok, response_text} <-
           Agents.chat(@assistant_name, prompt, %{source: "freeform_grader"}),
         {:ok, result} <- parse_response(response_text) do
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error(
          "[FreeformGrader] AI grading failed, falling back to exact match: #{inspect(reason)}"
        )

        {:ok, %{correct: Grading.correct?(question, student_answer), feedback: nil}}
    end
  end

  defp ensure_assistant do
    Agents.resolve_or_create_assistant(assistant_attrs())
  end

  defp build_prompt(question, student_answer) do
    reference_answer = Map.get(question, :answer) || Map.get(question, "answer") || ""
    question_content = Map.get(question, :content) || Map.get(question, "content") || ""

    """
    Question: #{question_content}

    Reference answer: #{reference_answer}

    Student's answer: #{student_answer}
    """
  end

  defp parse_response(text) do
    cleaned =
      text
      |> String.trim()
      |> strip_markdown_code_fence()

    case Jason.decode(cleaned) do
      {:ok, %{"correct" => correct} = parsed} when is_boolean(correct) ->
        feedback =
          case Map.get(parsed, "feedback") do
            val when is_binary(val) and val != "" -> val
            _ -> nil
          end

        {:ok, %{correct: correct, feedback: feedback}}

      {:ok, other} ->
        Logger.warning("[FreeformGrader] Unexpected JSON shape: #{inspect(other)}")
        {:error, :unexpected_shape}

      {:error, reason} ->
        Logger.warning("[FreeformGrader] Failed to parse AI response as JSON: #{inspect(reason)}")
        {:error, :json_parse_failed}
    end
  end

  defp strip_markdown_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end
end
