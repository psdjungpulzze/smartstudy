defmodule FunSheep.Workers.MaterialClassificationWorker do
  @moduledoc """
  Oban worker that AI-classifies an uploaded material's content and
  writes the result back to `uploaded_materials.classified_kind`.

  Runs after OCR completes. The result is consulted by downstream
  workers (Phase 3 Q&A extractor, Phase 4 AI generator) so they route
  on the VERIFIED content kind rather than the user-supplied
  `material_kind`. This is the guardrail that prevents the mid-April
  prod incident from recurring: an answer-key image uploaded as
  `:textbook` produced 462 garbage questions because the extractor
  trusted the user label.

  The worker does NOT touch `material_kind` — that's the user's
  declared intent and we preserve it for audit / admin reconcile UI.
  Routing logic reads `classified_kind` first, falls back to
  `material_kind` only when confidence is low.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 20,
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Content.MaterialClassifier

  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)

    cond do
      material.ocr_status != :completed ->
        # Race with the OCR dispatcher — try again shortly. Tell Oban to
        # retry instead of marking done.
        Logger.info("[MaterialClassify] Material #{material_id} OCR not complete yet")
        {:snooze, 30}

      material.classified_kind != nil ->
        # Already classified — idempotent no-op so re-enqueues from
        # retries don't repeat the LLM call.
        :ok

      true ->
        text = collect_ocr_text(material_id)
        subject = course_subject(material.course_id)

        case MaterialClassifier.classify(text, subject: subject) do
          {:ok, %{kind: kind, confidence: conf, notes: notes}} ->
            Content.update_uploaded_material(material, %{
              classified_kind: kind,
              kind_confidence: conf,
              kind_classification_notes: notes,
              kind_classified_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

            log_mismatch_if_any(material, kind)
            Logger.info("[MaterialClassify] #{material_id}: #{kind} (conf=#{conf})")
            :ok

          {:error, reason} ->
            Logger.warning("[MaterialClassify] #{material_id} failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Enqueue a classification job for a single material. Called by the
  OCR pipeline once OCR completes.
  """
  def enqueue(material_id) do
    %{material_id: material_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Routing helper used by the Q&A extractor and AI generator to decide
  what to do with a material. Trusts `classified_kind` when set, falls
  back to the legacy `material_kind` map.

  Returns one of:
    * `:extract`    — run the Q&A extractor on this material
    * `:ground`     — feed this material to the AI generator as
                      grounding text (do NOT try to extract questions
                      from it — it's prose)
    * `:extract_and_ground` — mixed content; both paths apply
    * `:skip`       — do not extract or ground (answer key / unusable)
    * `:review`     — uncertain; admin should resolve
  """
  @spec route(%FunSheep.Content.UploadedMaterial{}) ::
          :extract | :ground | :extract_and_ground | :skip | :review
  def route(%{classified_kind: :question_bank}), do: :extract
  def route(%{classified_kind: :knowledge_content}), do: :ground
  def route(%{classified_kind: :mixed}), do: :extract_and_ground
  def route(%{classified_kind: :answer_key}), do: :skip
  def route(%{classified_kind: :unusable}), do: :skip
  def route(%{classified_kind: :uncertain}), do: :review

  # Classifier hasn't run yet — fall back to the user-supplied
  # material_kind so upgrades don't break courses whose materials
  # predate the classifier.
  def route(%{classified_kind: nil, material_kind: :sample_questions}), do: :extract
  def route(%{classified_kind: nil, material_kind: :textbook}), do: :ground
  def route(%{classified_kind: nil, material_kind: :supplementary_book}), do: :ground
  def route(%{classified_kind: nil, material_kind: :lecture_notes}), do: :ground
  def route(%{classified_kind: nil, material_kind: :syllabus}), do: :ground
  def route(%{classified_kind: nil, material_kind: _}), do: :review

  # -- helpers ----------------------------------------------------------------

  defp collect_ocr_text(material_id) do
    from(p in Content.OcrPage,
      where: p.material_id == ^material_id,
      order_by: [asc: p.page_number],
      select: p.extracted_text
    )
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp course_subject(nil), do: nil

  defp course_subject(course_id) do
    case Courses.get_course!(course_id) do
      %{subject: s} -> s
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Flag user/classifier mismatches for admin review. These are the
  # most interesting rows — a `:textbook` upload that classifier tagged
  # `:answer_key` is exactly the mid-April failure mode caught live.
  defp log_mismatch_if_any(%{material_kind: user_kind} = material, classified_kind) do
    if mismatch?(user_kind, classified_kind) do
      Logger.warning(
        "[MaterialClassify] MISMATCH material=#{material.id} user=#{user_kind} classified=#{classified_kind}"
      )
    end
  end

  # Semantic equivalence between user-facing `material_kind` and
  # AI `classified_kind`. Kept as a single table so the "what counts as
  # a mismatch" rule is trivial to audit.
  defp mismatch?(:sample_questions, :question_bank), do: false
  defp mismatch?(:textbook, :knowledge_content), do: false
  defp mismatch?(:supplementary_book, :knowledge_content), do: false
  defp mismatch?(:lecture_notes, :knowledge_content), do: false
  defp mismatch?(:syllabus, :knowledge_content), do: false
  defp mismatch?(_, :uncertain), do: false
  defp mismatch?(_, :unusable), do: false
  defp mismatch?(_, _), do: true
end
