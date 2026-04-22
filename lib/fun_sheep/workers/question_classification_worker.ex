defmodule FunSheep.Workers.QuestionClassificationWorker do
  @moduledoc """
  Oban worker that assigns a fine-grained skill tag (`section_id`) to questions
  that lack one. Implements the backfill side of North Star invariant I-1.

  Honesty gate (I-15): the worker only writes `section_id` + `:ai_classified`
  when confidence exceeds the threshold AND the predicted section already
  exists. Below-threshold OR "propose a new section" cases become
  `:low_confidence` and surface to the admin review queue.
  """

  # `unique` prevents duplicate classification jobs from piling up when the
  # same chapter or batch is enqueued by multiple callers. Order is normalized
  # in `enqueue_for_questions/1`.
  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [
      period: 120,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Questions.Question
  alias FunSheep.Interactor.Agents

  import Ecto.Query
  require Logger

  @default_confidence_threshold 0.85

  # Interactor only applies `assistant_attrs` on first provision, so pushing
  # a config change (model, prompt, token cap) requires registering under a
  # new name. Prior names: "question_classifier", "question_classifier_v1".
  # If config must change again, pick another descriptive name rather than
  # reusing a prior one.
  @assistant_name "question_skill_tagger"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    questions = load_questions(args)

    if questions == [] do
      Logger.info("[QClassify] No uncategorized questions for args=#{inspect(args)}")
      :ok
    else
      Logger.info("[QClassify] Classifying #{length(questions)} questions")

      Enum.each(questions, fn q ->
        sections = Courses.list_sections_by_chapter(q.chapter_id)
        classify_one(q, sections)
      end)

      :ok
    end
  end

  def enqueue_for_chapter(chapter_id) do
    %{"chapter_id" => chapter_id} |> new() |> Oban.insert()
  end

  def enqueue_for_questions(question_ids) when is_list(question_ids) and question_ids != [] do
    %{"question_ids" => Enum.sort(question_ids)} |> new() |> Oban.insert()
  end

  def enqueue_for_questions(_), do: {:ok, :noop}

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
    mark_low_confidence(question, nil, %{reason: "no_sections_in_chapter"})
  end

  defp classify_one(question, sections) do
    prompt = build_prompt(question, sections)

    # Provisioning failures must short-circuit — otherwise Agents.chat/3 hits
    # Interactor with an unknown assistant name and every call returns
    # :assistant_not_found (prod incident 2026-04-22: 530 questions failed
    # this way before the name was bumped).
    case ensure_assistant() do
      {:ok, _id} ->
        case agents_impl().chat(@assistant_name, prompt, %{
               source: "question_classification_worker",
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

      {:error, reason} ->
        Logger.error(
          "[QClassify] Assistant not provisioned for #{question.id}; leaving for retry: #{inspect(reason)}"
        )

        {:error, :assistant_unavailable}
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

    Return ONLY a JSON object:
    {
      "section_id": "<uuid of matched section, or null>",
      "propose_section_name": "<name of a new section if none fit, or null>",
      "confidence": <float 0.0-1.0>,
      "rationale": "<one-sentence explanation>"
    }

    Prefer matching an existing section. Return low confidence (<0.6) if unsure.
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

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp confidence_threshold do
    Application.get_env(
      :fun_sheep,
      :classification_confidence_threshold,
      @default_confidence_threshold
    )
  end

  @behaviour FunSheep.Interactor.AssistantSpec

  @doc """
  Configuration used to register the `#{@assistant_name}` assistant on
  Interactor. Exposed for scripts/preflight checks.
  """
  @impl FunSheep.Interactor.AssistantSpec
  def assistant_attrs do
    %{
      name: @assistant_name,
      description:
        "Classifies a question into one of a chapter's existing sections (skill tag). Returns a JSON verdict with section_id and confidence.",
      system_prompt:
        "You are a curriculum skill tagger. Given a question and the list of sections in its chapter, pick the single best existing section. If nothing fits, return null and propose a name. Always return a low confidence when unsure.",
      llm_provider: "openai",
      llm_model: "gpt-4o-mini",
      llm_config: %{temperature: 0.1, max_tokens: 400},
      metadata: %{app: "funsheep", role: "question_classifier"}
    }
  end

  @doc """
  Ensures the classifier assistant exists on Interactor. Safe to call
  repeatedly — cached in `persistent_term`.
  """
  def ensure_assistant do
    case :persistent_term.get({__MODULE__, :assistant_id}, nil) do
      nil ->
        provision_assistant()

      id ->
        {:ok, id}
    end
  end

  defp provision_assistant do
    # Race-safe: if a peer just created the assistant, we'll re-resolve
    # instead of fighting a 422.
    case agents_impl().resolve_or_create_assistant(assistant_attrs()) do
      {:ok, id} ->
        :persistent_term.put({__MODULE__, :assistant_id}, id)
        {:ok, id}

      {:error, _} = err ->
        err
    end
  end

  # Routes Agents calls through a configurable impl so tests can stub the
  # Interactor round-trip without real HTTP. Production always resolves to
  # `FunSheep.Interactor.Agents`; tests set this to a Mox-backed stub.
  defp agents_impl do
    Application.get_env(:fun_sheep, :interactor_agents_impl, Agents)
  end
end
