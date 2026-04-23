defmodule FunSheep.Content.MaterialClassifier do
  @moduledoc """
  AI-backed classifier that inspects OCR text (or scraped web content)
  and decides what KIND of material it actually is.

  The existing `uploaded_material.material_kind` is user-supplied and
  untrusted — the mid-April prod audit found an answer-key image
  (`Biology Answers - 31.jpg`) uploaded as `:textbook` that produced
  462 garbage questions through the regex extractor. The classifier is
  the guardrail: run on every material post-OCR and on every scraped
  page post-scrape, then route extraction/generation based on the
  AI-verified kind, not the user label.

  Output kinds (superset of the user-facing `material_kind`):

  * `:question_bank`     — practice sets, past exams, chapter-review
                           question sets. The Q&A extractor (Phase 3)
                           runs on these.
  * `:answer_key`        — answer tables only, no question stems.
                           Extraction is SKIPPED; admin is flagged.
  * `:knowledge_content` — textbook prose, study guides, lecture
                           notes. The AI generator (Phase 4) consumes
                           these as grounding text.
  * `:mixed`             — both questions AND prose, interleaved. Can
                           be fed to both extractor and generator; the
                           extractor must tolerate surrounding prose.
  * `:unusable`          — blank pages, cover pages, index-only,
                           duplicates, OCR noise.
  * `:uncertain`         — classifier confidence below the floor;
                           admin review.

  The caller decides how to route each kind (see
  `MaterialClassificationWorker.route/1`). This module is pure: input
  text → `{kind, confidence, notes}`.
  """

  require Logger

  @assistant_name "material_content_classifier"

  # Below this floor we write `:uncertain` — the classifier saw
  # something but wasn't sure enough to authorize extraction. Tuned
  # conservatively: `:answer_key` false-negatives (labeled as
  # `:question_bank`) are the specific failure mode we're defending
  # against, so we err on the side of admin review.
  @default_confidence_floor 0.6

  @type kind ::
          :question_bank
          | :answer_key
          | :knowledge_content
          | :mixed
          | :unusable
          | :uncertain

  @type classification :: %{
          kind: kind,
          confidence: float,
          notes: String.t() | nil
        }

  @doc """
  Classify a chunk of text. Returns a `classification` map.

  `opts`:
    * `:confidence_floor` — (default 0.6) anything below this maps to
      `:uncertain` even if the LLM returned something else.
    * `:subject` — optional course subject to help the classifier
      disambiguate (e.g. an answer key for AP Biology vs for AP Chem).
  """
  @spec classify(String.t(), keyword) :: {:ok, classification} | {:error, term}
  def classify(text, opts \\ []) when is_binary(text) do
    if String.length(String.trim(text)) < 40 do
      # Too little text to classify meaningfully — treat as unusable
      # so the pipeline doesn't fire an LLM call on a blank page.
      {:ok,
       %{
         kind: :unusable,
         confidence: 1.0,
         notes: "OCR text too short (<40 chars) to classify"
       }}
    else
      prompt = build_prompt(text, opts)

      case agents_impl().chat(@assistant_name, prompt, %{
             source: "material_classifier",
             metadata: %{subject: opts[:subject]}
           }) do
        {:ok, response} ->
          parse_response(
            response,
            Keyword.get(opts, :confidence_floor, @default_confidence_floor)
          )

        {:error, reason} ->
          Logger.warning("[MaterialClassifier] Agent call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # -- prompt -----------------------------------------------------------------

  defp build_prompt(text, opts) do
    subject_line =
      case opts[:subject] do
        nil -> ""
        s -> "Course subject: #{s}\n\n"
      end

    # Deliberately show truncated text — the classifier doesn't need the
    # full 200-page textbook to decide "this is textbook prose." Sampling
    # the first ~6000 chars keeps per-call cost bounded while still
    # capturing layout signals (headers, numbering patterns, A/B/C/D lists).
    sampled = sample_text(text)

    """
    Classify the following material. Read the excerpt and decide which
    single category best describes it. The categories are:

    * question_bank      — Practice questions (stems + options or
                           stems + expected answers). Examples: chapter
                           review questions, past exam questions,
                           sample-question PDFs.
    * answer_key         — Only answer letters/indices, no question
                           stems. Examples: "1. C  2. B  3. D  4. A"
                           repeated page after page. This is NOT a
                           question bank — there are no questions here.
    * knowledge_content  — Textbook prose, study guide summaries,
                           lecture notes, glossary, diagrams. Learning
                           material, not questions.
    * mixed              — Questions AND surrounding prose interleaved
                           (e.g. a worked example with a question at
                           the end).
    * unusable           — Blank, cover page, copyright page, index
                           only, table of contents, OCR noise with no
                           meaningful content.

    #{subject_line}Excerpt (#{String.length(text)} chars total; showing up to 6000):
    ---
    #{sampled}
    ---

    Return ONLY a JSON object (no markdown, no array) with this exact
    shape:
    {
      "kind": "question_bank" | "answer_key" | "knowledge_content" | "mixed" | "unusable",
      "confidence": 0.0..1.0,
      "notes": "one-sentence explanation of the signal you used"
    }
    """
  end

  defp sample_text(text) do
    # First 6000 chars; if the text is longer, append a separator and
    # the last 1500 so we catch layout cues from the end (e.g. an answer
    # key appended to a question bank).
    length = String.length(text)

    if length <= 6000 do
      text
    else
      head = String.slice(text, 0, 6000)
      tail = String.slice(text, length - 1500, 1500)
      head <> "\n\n[... middle omitted ...]\n\n" <> tail
    end
  end

  # -- response parsing -------------------------------------------------------

  defp parse_response(text, floor) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    with {:ok, decoded} <- Jason.decode(cleaned),
         {:ok, kind} <- normalize_kind(decoded["kind"]),
         {:ok, confidence} <- normalize_confidence(decoded["confidence"]) do
      final_kind = if confidence < floor, do: :uncertain, else: kind

      {:ok,
       %{
         kind: final_kind,
         confidence: confidence,
         notes: decoded["notes"]
       }}
    else
      {:error, reason} ->
        Logger.warning("[MaterialClassifier] Unparseable response: #{inspect(reason)}")
        {:error, :unparseable_response}
    end
  end

  defp normalize_kind("question_bank"), do: {:ok, :question_bank}
  defp normalize_kind("answer_key"), do: {:ok, :answer_key}
  defp normalize_kind("knowledge_content"), do: {:ok, :knowledge_content}
  defp normalize_kind("mixed"), do: {:ok, :mixed}
  defp normalize_kind("unusable"), do: {:ok, :unusable}
  defp normalize_kind(_), do: {:error, :unknown_kind}

  defp normalize_confidence(c) when is_number(c) and c >= 0 and c <= 1, do: {:ok, c * 1.0}
  defp normalize_confidence(c) when is_number(c) and c >= 0 and c <= 100, do: {:ok, c / 100.0}
  defp normalize_confidence(_), do: {:error, :bad_confidence}

  @behaviour FunSheep.Interactor.AssistantSpec

  # Configurable impl so tests can stub the Interactor round-trip.
  # Production resolves to `FunSheep.Interactor.Agents`; tests set this
  # via `Application.put_env(:fun_sheep, :interactor_agents_impl, Mock)`.
  defp agents_impl do
    Application.get_env(:fun_sheep, :interactor_agents_impl, FunSheep.Interactor.Agents)
  end

  @impl FunSheep.Interactor.AssistantSpec
  def assistant_attrs do
    %{
      name: @assistant_name,
      description:
        "Classifies uploaded course material (OCR text or scraped web content) into question_bank / answer_key / knowledge_content / mixed / unusable. Returns JSON with kind + confidence.",
      system_prompt:
        "You are a content classifier for an educational platform. Read the excerpt and decide the single best category. Be especially careful to distinguish answer_key (only letters/indices, no question stems) from question_bank — mis-routing an answer key as questions produces garbage content. When unsure, return lower confidence rather than guessing.",
      llm_provider: "openai",
      llm_model: "gpt-4o-mini",
      llm_config: %{temperature: 0.0, max_tokens: 200},
      metadata: %{app: "funsheep", role: "material_classifier"}
    }
  end
end
