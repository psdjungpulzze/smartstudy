defmodule FunSheep.Assessments.FormatParser do
  @moduledoc """
  Parses free-form test format descriptions into structured section definitions.

  Teachers often write format specs like:
    "20 MC (30 min)\nFRQ: 1 long - 7pts, 3 - 3pt questions (35 min)"
  or:
    "Chapter 2~42, except 30 — 40 multiple choices"

  The parser sends the raw text to an AI assistant and returns a list of
  sections compatible with `TestFormatTemplate.structure["sections"]`, plus
  an optional overall time limit.
  """

  @behaviour FunSheep.Interactor.AssistantSpec

  alias FunSheep.Interactor.Agents

  require Logger

  @assistant_name "funsheep_format_parser"

  @system_prompt """
  You parse test format descriptions written by teachers into structured JSON.

  Given a free-form format description, extract test sections and return ONLY valid JSON — no markdown, no explanation.

  Output format:
  {
    "sections": [
      {
        "name": "Section display name",
        "question_type": "multiple_choice|short_answer|free_response|true_false",
        "count": <integer number of questions>,
        "points_per_question": <integer, default 1 if not specified>,
        "time_minutes": <integer or null>
      }
    ],
    "time_limit_minutes": <total time as integer, or null if not specified>
  }

  Question type mapping rules:
  - "MC", "multiple choice", "MCQ" → "multiple_choice"
  - "FRQ", "free response", "long answer" → "free_response"
  - "short answer", "SA" → "short_answer"
  - "T/F", "true/false", "true or false" → "true_false"
  - Default to "multiple_choice" if ambiguous

  Points rules:
  - If not specified, default to 1 point per question
  - "3-pt questions" means points_per_question = 3
  - "7pts" on a single question means points_per_question = 7

  Time rules:
  - Capture per-section time in time_minutes if specified
  - Set time_limit_minutes to the sum of all section times if no total is given
  - Set time_limit_minutes to null if no time info at all

  Be liberal in parsing — teachers write casually. Always return valid JSON.
  If nothing can be extracted, return {"sections": [], "time_limit_minutes": null}.
  """

  @impl FunSheep.Interactor.AssistantSpec
  def assistant_attrs do
    %{
      name: @assistant_name,
      description: "Parses free-form test format descriptions into structured section definitions",
      system_prompt: @system_prompt,
      llm_provider: "anthropic",
      llm_model: "claude-haiku-4-5-20251001",
      llm_config: %{temperature: 0.0, max_tokens: 512},
      metadata: %{app: "funsheep", role: "format_parser"}
    }
  end

  @doc """
  Parses a free-form format string into structured sections.

  Returns `{:ok, %{sections: [...], time_limit_minutes: integer | nil}}`
  or `{:error, reason}`.
  """
  @spec parse(String.t()) ::
          {:ok, %{sections: [map()], time_limit_minutes: integer() | nil}}
          | {:error, term()}
  def parse(format_text) when is_binary(format_text) and format_text != "" do
    with {:ok, _} <- ensure_assistant(),
         {:ok, response} <- Agents.chat(@assistant_name, format_text, %{source: "format_parser"}),
         {:ok, parsed} <- decode_response(response) do
      {:ok, parsed}
    else
      {:error, reason} ->
        Logger.error("[FormatParser] Failed to parse format: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def parse(_), do: {:error, :empty_input}

  defp ensure_assistant do
    Agents.resolve_or_create_assistant(assistant_attrs())
  end

  defp decode_response(text) do
    cleaned = text |> String.trim() |> strip_markdown_fences()

    case Jason.decode(cleaned) do
      {:ok, %{"sections" => sections} = result} ->
        normalized = %{
          sections: Enum.map(sections, &normalize_section/1),
          time_limit_minutes: result["time_limit_minutes"]
        }

        {:ok, normalized}

      {:ok, _} ->
        {:error, :unexpected_shape}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp strip_markdown_fences(text) do
    text
    |> String.replace(~r/^```json\n?/, "")
    |> String.replace(~r/^```\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end

  defp normalize_section(section) do
    %{
      "name" => section["name"] || "Section",
      "question_type" => coerce_question_type(section["question_type"]),
      "count" => coerce_int(section["count"], 1),
      "points_per_question" => coerce_int(section["points_per_question"], 1),
      "chapter_ids" => []
    }
    |> maybe_put_time(section["time_minutes"])
  end

  defp maybe_put_time(section, nil), do: section
  defp maybe_put_time(section, mins), do: Map.put(section, "time_minutes", mins)

  @valid_types ~w(multiple_choice short_answer free_response true_false)

  defp coerce_question_type(t) when t in @valid_types, do: t
  defp coerce_question_type(_), do: "multiple_choice"

  defp coerce_int(val, _default) when is_integer(val) and val > 0, do: val

  defp coerce_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp coerce_int(_, default), do: default
end
