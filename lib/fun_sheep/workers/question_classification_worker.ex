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
    max_attempts: 20,
    unique: [
      period: 120,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Courses.Course
  alias FunSheep.Questions.Question

  import Ecto.Query
  require Logger

  # Default lowered from 0.85 → 0.5 on 2026-04-22. The original threshold was
  # set conservatively against the I-1 invariant (only adaptive-eligible
  # questions reach students), but in production gpt-4o-mini's calibrated
  # confidence on real chapter→section mapping for AP Biology landed in the
  # 0.5–0.7 range *for valid* assignments — so 0.85 rejected nearly every
  # otherwise-good classification, leaving 925 questions stuck at
  # :low_confidence and invisible to delivery (course d44628ca incident).
  # 0.5 is the floor below which the LLM is genuinely guessing; the
  # `valid_section_id` check (section must exist in this chapter) prevents
  # randomly-confident-but-wrong assignments from leaking through.
  # Override via `CLASSIFIER_CONFIDENCE_THRESHOLD` env var for tuning.
  @default_confidence_threshold 0.5

  @system_prompt "You are a curriculum skill tagger. Given a question and the list of sections in its chapter, pick the single best existing section. If nothing fits, return null and propose a name. Always return a low confidence when unsure."

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 400,
    temperature: 0.1,
    source: "question_classification_worker"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    questions = load_questions(args)

    if questions == [] do
      Logger.info("[QClassify] No uncategorized questions for args=#{inspect(args)}")
      :ok
    else
      course_id = hd(questions).course_id
      course = Repo.get(Course, course_id)

      if course && course.processing_status == "cancelled" do
        Logger.info("[QClassify] Skipped cancelled course #{course_id}")
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

  # When the chapter has no sections, the LLM has nothing to classify against
  # and the question would otherwise rot at :low_confidence — invisible to
  # practice / quick-test / readiness (see North Star invariant I-1). Auto-
  # provision a single "Overview" section so the chapter satisfies I-1 and
  # mark the question as :ai_classified directly: with only one possible
  # section, an LLM call would be wasted.
  #
  # This unblocked the 2026-04-22 incident where AP Biology had 793 :passed
  # questions classifier-rotted at :low_confidence because the discovery
  # worker emitted chapters without a `sections` array.
  defp classify_one(question, sections) when sections == [] do
    case Courses.ensure_default_section(question.chapter_id) do
      {:ok, section} ->
        mark_classified(question, section.id, 1.0, %{
          rationale: "auto-assigned to default Overview section (chapter has no other sections)",
          auto_default: true
        })

      {:error, reason} ->
        Logger.error(
          "[QClassify] Could not provision default section for chapter " <>
            "#{question.chapter_id}: #{inspect(reason)}"
        )

        mark_low_confidence(question, nil, %{
          reason: "default_section_provisioning_failed",
          error: inspect(reason)
        })
    end
  end

  defp classify_one(question, sections) do
    prompt = build_prompt(question, sections)

    case ai_client().call(@system_prompt, prompt, @llm_opts) do
      {:ok, response} ->
        case parse_response(response, sections) do
          {:ok, parsed} ->
            apply_classification(question, sections, parsed)

          {:error, reason} ->
            Logger.warning("[QClassify] Parse failed for #{question.id}: #{inspect(reason)}")
            {:error, :parse_failed}
        end

      {:error, reason} ->
        Logger.error("[QClassify] LLM call failed for #{question.id}: #{inspect(reason)}")
        {:error, :ai_unavailable}
    end
  end

  # Pick-by-number prompt: tells the LLM to return an integer 1..N
  # instead of a UUID. UUIDs are 36-char strings the model rarely
  # reproduces verbatim, so the old prompt's `valid_section_id` check
  # rejected ~80% of verdicts even when the LLM correctly identified the
  # right section in the rationale (the 2026-04-22 prod incident:
  # confidence 0.5–0.7 with hallucinated UUIDs → :low_confidence). We
  # then map number → real UUID in `parse_response/2` so hallucination is
  # impossible by construction.
  defp build_prompt(question, sections) do
    sections_list =
      sections
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {s, idx} -> "#{idx}. #{s.name}" end)

    """
    Classify the following question into one of the existing sections for this chapter.

    SECTIONS (pick by number):
    #{sections_list}

    QUESTION:
    #{question.content}

    Return ONLY a JSON object:
    {
      "section_number": <integer 1-#{length(sections)}, or null if none fit>,
      "propose_section_name": "<name of a new section if none fit, or null>",
      "confidence": <float 0.0-1.0>,
      "rationale": "<one-sentence explanation>"
    }

    Pick the closest existing section. Use `section_number: null` ONLY when
    no listed section is even loosely related. Confidence below 0.6 means
    you're guessing.
    """
  end

  defp parse_response(text, sections) when is_binary(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    with {:ok, %{"confidence" => conf} = json} when is_number(conf) <- Jason.decode(cleaned) do
      section_id = resolve_section(json, sections)

      {:ok,
       %{
         section_id: section_id,
         propose_section_name: json["propose_section_name"],
         confidence: conf / 1.0,
         rationale: json["rationale"]
       }}
    else
      _ -> {:error, :bad_json}
    end
  end

  # Map "section_number" 1..N → the corresponding section's UUID.
  # Falls back to "section_id" for any caller still using the old shape
  # (and for forward-compat if the LLM occasionally returns a UUID).
  defp resolve_section(%{"section_number" => n}, sections)
       when is_integer(n) and n >= 1 do
    case Enum.at(sections, n - 1) do
      nil -> nil
      section -> section.id
    end
  end

  defp resolve_section(%{"section_id" => sid}, _sections) when is_binary(sid), do: sid
  defp resolve_section(_, _), do: nil

  defp apply_classification(question, sections, %{
         section_id: section_id,
         propose_section_name: proposed,
         confidence: confidence,
         rationale: rationale
       }) do
    threshold = confidence_threshold()

    # Boolean (not nil) so the `cond` below doesn't BadBooleanError when
    # section_id is nil — which it now is whenever resolve_section/2 can't
    # map the LLM's section_number to a real UUID.
    valid_section_id = is_binary(section_id) and Enum.any?(sections, &(&1.id == section_id))

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

    result =
      question
      |> Question.changeset(%{
        section_id: section_id,
        classification_status: :ai_classified,
        classification_confidence: confidence,
        classified_at: now,
        metadata: Map.merge(question.metadata || %{}, %{"classification" => stringify(meta)})
      })
      |> Repo.update()

    # A question becomes student-visible (and adaptive-eligible) only after
    # both validation has passed AND classification has tagged it. Since
    # classification typically runs last, this is where we let subscribers —
    # notably `AssessmentLive` — know the scope may have just tipped into
    # `:ready`. No-op when the update itself failed.
    with {:ok, updated} <- result do
      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        "course:#{updated.course_id}",
        {:questions_ready, %{chapter_ids: [updated.chapter_id]}}
      )

      result
    end
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

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
