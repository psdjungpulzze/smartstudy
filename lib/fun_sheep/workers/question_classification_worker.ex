defmodule FunSheep.Workers.QuestionClassificationWorker do
  @moduledoc """
  Oban worker that assigns a fine-grained skill tag (`section_id`) to questions
  that lack one. Implements the backfill side of North Star invariant I-1.

  Honesty gate (invariant I-15): the worker only writes `section_id` and marks
  a question as `:ai_classified` when the model's confidence exceeds the
  configured threshold AND the predicted section already exists in the taxonomy.
  When the model wants to propose a new section, OR when confidence is below
  threshold, the question is marked `:low_confidence` and surfaced to the admin
  review queue — we never silently expand the taxonomy, and we never tag on
  thin evidence.

  Args:
    * `"chapter_id"` — classify every `:uncategorized` question in that chapter
    * `"question_ids"` — classify just this list (overrides chapter_id)

  One question per AI call. Batching is a future optimization; single-shot
  keeps failure modes per-row and auditable.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Questions.Question
  alias FunSheep.Interactor.Agents

  import Ecto.Query
  require Logger

  @default_confidence_threshold 0.85

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    questions = load_questions(args)

    if questions == [] do
      Logger.info("[QClassify] No uncategorized questions for args=#{inspect(args)}")
      :ok
    else
      Logger.info("[QClassify] Classifying #{length(questions)} questions")

      results =
        Enum.map(questions, fn q ->
          sections = Courses.list_sections_by_chapter(q.chapter_id)
          classify_one(q, sections)
        end)

      summary = summarize(results)
      Logger.info("[QClassify] Done: #{inspect(summary)}")
      :ok
    end
  end

  @doc """
  Convenience enqueuer used by AIQuestionGenerationWorker and admin actions.
  """
  def enqueue_for_chapter(chapter_id) do
    %{"chapter_id" => chapter_id} |> new() |> Oban.insert()
  end

  def enqueue_for_questions(question_ids) when is_list(question_ids) and question_ids != [] do
    %{"question_ids" => question_ids} |> new() |> Oban.insert()
  end

  def enqueue_for_questions(_), do: {:ok, :noop}

  # --- Private ---

  defp load_questions(%{"question_ids" => ids}) when is_list(ids) and ids != [] do
    from(q in Question,
      where:
        q.id in ^ids and q.classification_status == :uncategorized and
          not is_nil(q.chapter_id)
    )
    |> Repo.all()
  end

  defp load_questions(%{"chapter_id" => chapter_id}) when not is_nil(chapter_id) do
    from(q in Question,
      where: q.chapter_id == ^chapter_id and q.classification_status == :uncategorized
    )
    |> Repo.all()
  end

  defp load_questions(_), do: []

  defp classify_one(question, sections) when sections == [] do
    # No existing sections in this chapter — we can't match into an existing
    # tag, and auto-creating sections would expand the taxonomy silently.
    # Mark as low-confidence so an admin can review and seed sections.
    mark_low_confidence(question, nil, %{reason: "no_sections_in_chapter"})
  end

  defp classify_one(question, sections) do
    prompt = build_prompt(question, sections)

    case Agents.chat("question_classifier", prompt, %{
           metadata: %{question_id: question.id, chapter_id: question.chapter_id}
         }) do
      {:ok, response} ->
        case parse_response(response) do
          {:ok, parsed} ->
            apply_classification(question, sections, parsed)

          {:error, reason} ->
            Logger.warning("[QClassify] Parse failed for #{question.id}: #{inspect(reason)}")
            {:error, :parse_failed}
        end

      {:error, reason} ->
        Logger.error("[QClassify] AI unavailable for #{question.id}: #{inspect(reason)}")
        {:error, :ai_unavailable}
    end
  end

  defp build_prompt(question, sections) do
    sections_list =
      Enum.map_join(sections, "\n", fn s -> "- id=#{s.id} | name=#{s.name}" end)

    """
    Classify the following question into one of the existing sections for this chapter.

    EXISTING SECTIONS:
    #{sections_list}

    QUESTION:
    #{question.content}

    Return ONLY a JSON object with this exact shape:
    {
      "section_id": "<uuid of matched section, or null if none fits>",
      "propose_section_name": "<name of a new section if none of the existing ones fit, or null>",
      "confidence": <float between 0.0 and 1.0>,
      "rationale": "<one-sentence explanation>"
    }

    Rules:
    - Prefer matching to an existing section. Only propose a new section if no existing one is a reasonable fit.
    - `confidence` reflects how certain you are the question belongs to the returned tag.
    - If you are unsure, return a low confidence (<0.6) rather than guessing.
    """
  end

  defp parse_response(text) when is_binary(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"confidence" => conf} = json} when is_number(conf) ->
        {:ok,
         %{
           section_id: json["section_id"],
           propose_section_name: json["propose_section_name"],
           confidence: conf / 1.0,
           rationale: json["rationale"]
         }}

      _ ->
        {:error, :bad_json}
    end
  end

  defp apply_classification(question, sections, %{
         section_id: section_id,
         propose_section_name: proposed,
         confidence: confidence,
         rationale: rationale
       }) do
    threshold = confidence_threshold()
    valid_section_id = section_id && Enum.any?(sections, &(&1.id == section_id))

    cond do
      valid_section_id and confidence >= threshold ->
        mark_classified(question, section_id, confidence, %{rationale: rationale})

      # Model proposed a new section — never silently expand the taxonomy,
      # send to admin review regardless of reported confidence.
      is_binary(proposed) and proposed != "" ->
        mark_low_confidence(question, confidence, %{
          rationale: rationale,
          propose_section_name: proposed
        })

      true ->
        mark_low_confidence(question, confidence, %{
          rationale: rationale,
          rejected: "below_threshold_or_invalid_section_id"
        })
    end
  end

  defp mark_classified(question, section_id, confidence, meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    question
    |> Question.changeset(%{
      section_id: section_id,
      classification_status: :ai_classified,
      classification_confidence: confidence,
      classified_at: now,
      metadata: Map.merge(question.metadata || %{}, %{"classification" => stringify(meta)})
    })
    |> Repo.update()
  end

  defp mark_low_confidence(question, confidence, meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    question
    |> Question.changeset(%{
      classification_status: :low_confidence,
      classification_confidence: confidence,
      classified_at: now,
      metadata: Map.merge(question.metadata || %{}, %{"classification" => stringify(meta)})
    })
    |> Repo.update()
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp confidence_threshold do
    Application.get_env(
      :fun_sheep,
      :classification_confidence_threshold,
      @default_confidence_threshold
    )
  end

  defp summarize(results) do
    Enum.reduce(results, %{classified: 0, low_confidence: 0, failed: 0}, fn
      {:ok, %Question{classification_status: :ai_classified}}, acc ->
        Map.update!(acc, :classified, &(&1 + 1))

      {:ok, %Question{classification_status: :low_confidence}}, acc ->
        Map.update!(acc, :low_confidence, &(&1 + 1))

      _, acc ->
        Map.update!(acc, :failed, &(&1 + 1))
    end)
  end
end
