defmodule FunSheep.Workers.TextbookCompletenessWorker do
  @moduledoc """
  Oban worker that verifies whether an uploaded textbook is _complete_.

  It reads the OCR text extracted from a `:textbook` material, asks the
  configured Interactor AI assistant (`textbook_completeness`) to extract
  the table of contents, and estimate how much of that TOC is actually
  present in the file.

  The AI's response is parsed as JSON with this shape:

      {
        "toc_detected": true | false,
        "chapters": ["Chapter 1 — …", …],
        "coverage_score": 0.0..1.0,
        "notes": "…"
      }

  Results are persisted on the `uploaded_materials` record in
  `completeness_score`, `completeness_notes`, `toc_detected`, and
  `completeness_checked_at`.

  Per project policy we never fabricate a score. If the assistant is
  unavailable, the response is unparseable, or OCR text is missing, the
  worker logs the failure and leaves `completeness_score` as `nil` so the
  UI can flag the material honestly.
  """

  use Oban.Worker, queue: :ai, max_attempts: 2

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Content.{OcrPage, UploadedMaterial}
  alias FunSheep.Interactor.Agents

  import Ecto.Query
  require Logger

  # Keep the prompt inside typical LLM context windows. 60k chars is roughly
  # 15k tokens — enough for a TOC and a generous sample of content.
  @max_chars 60_000
  @assistant_name "textbook_completeness"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)

    cond do
      material.material_kind != :textbook ->
        Logger.info(
          "[Completeness] Skipping non-textbook material #{material_id} (kind=#{material.material_kind})"
        )

        :ok

      material.ocr_status not in [:completed, :partial] ->
        Logger.info(
          "[Completeness] Skipping material #{material_id} (ocr_status=#{material.ocr_status})"
        )

        :ok

      true ->
        run(material)
    end
  end

  @doc "Enqueues a completeness check for the given material."
  def enqueue(material_id) do
    %{material_id: material_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # ── Implementation ────────────────────────────────────────────────────

  defp run(material) do
    text = collect_text(material.id)

    if text == "" do
      Logger.warning("[Completeness] No OCR text for material #{material.id}; failing honestly")

      {:ok, _} =
        Content.update_uploaded_material(material, %{
          completeness_score: nil,
          completeness_notes: "No OCR text was extracted from this file.",
          toc_detected: false,
          completeness_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      broadcast(material)
      :ok
    else
      course = if material.course_id, do: Courses.get_course!(material.course_id), else: nil
      prompt = build_prompt(material, course, text)

      case Agents.chat(@assistant_name, prompt, %{metadata: %{material_id: material.id}}) do
        {:ok, response} ->
          persist_result(material, response)

        {:error, reason} ->
          Logger.error(
            "[Completeness] Assistant call failed for material #{material.id}: #{inspect(reason)}"
          )

          {:ok, _} =
            Content.update_uploaded_material(material, %{
              completeness_score: nil,
              completeness_notes:
                "Completeness check could not run (#{format_reason(reason)}). " <>
                  "The textbook may still be usable; retry from the course page.",
              toc_detected: false,
              completeness_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          broadcast(material)
          {:error, reason}
      end
    end
  end

  defp persist_result(material, response) do
    case parse_response(response) do
      {:ok, parsed} ->
        {:ok, _} =
          Content.update_uploaded_material(material, %{
            completeness_score: parsed.score,
            completeness_notes: parsed.notes,
            toc_detected: parsed.toc_detected,
            completeness_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        Logger.info(
          "[Completeness] material=#{material.id} score=#{parsed.score} toc=#{parsed.toc_detected}"
        )

        broadcast(material)
        :ok

      {:error, reason} ->
        Logger.error(
          "[Completeness] Could not parse assistant response for #{material.id}: #{inspect(reason)}; raw=#{String.slice(response, 0, 500)}"
        )

        {:ok, _} =
          Content.update_uploaded_material(material, %{
            completeness_score: nil,
            completeness_notes: "Completeness check returned an unreadable response (#{reason}).",
            toc_detected: false,
            completeness_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        broadcast(material)
        {:error, reason}
    end
  end

  defp collect_text(material_id) do
    from(p in OcrPage,
      where: p.material_id == ^material_id,
      order_by: [asc: p.page_number],
      select: p.extracted_text
    )
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> sample_text()
  end

  defp sample_text(text) when byte_size(text) <= @max_chars, do: text

  defp sample_text(text) do
    half = div(@max_chars, 2)
    head = binary_part(text, 0, half)
    tail_offset = byte_size(text) - half
    tail = binary_part(text, tail_offset, half)
    head <> "\n\n---[truncated middle]---\n\n" <> tail
  end

  defp build_prompt(material, course, text) do
    course_context =
      case course do
        nil -> "Unknown course."
        %{} = c -> "Course: #{c.subject} (Grade #{c.grade}). Name: #{c.name}."
      end

    """
    You are validating whether the following text represents a COMPLETE textbook.

    #{course_context}
    File name: #{material.file_name}

    Instructions:
    1. Identify a table of contents (TOC) if present.
    2. Estimate what fraction of the TOC chapters have real content (not just
       an entry). A complete textbook has all listed chapters covered in the
       body.
    3. Respond with ONLY a JSON object — no markdown, no commentary — with
       these keys:
         - "toc_detected": boolean. True if a TOC was found.
         - "chapters": list of detected chapter titles (may be empty).
         - "coverage_score": number between 0.0 and 1.0. 1.0 = every TOC
           chapter has substantive content present; 0.0 = nothing matches.
           If no TOC can be found, use your best judgement based on overall
           structure (heading frequency, narrative completeness).
         - "notes": short human-readable explanation (1–3 sentences).

    Text (possibly truncated):
    ---
    #{text}
    ---
    """
  end

  # Accept either raw JSON or JSON wrapped in ```json fences.
  @doc false
  def parse_response(response) when is_binary(response) do
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{} = json} ->
        with {:ok, score} <- fetch_score(json),
             toc_detected <- json["toc_detected"] == true,
             notes <- stringify_notes(json) do
          {:ok, %{score: score, toc_detected: toc_detected, notes: notes}}
        end

      {:ok, _} ->
        {:error, :unexpected_json_shape}

      {:error, %Jason.DecodeError{}} ->
        {:error, :invalid_json}
    end
  end

  defp fetch_score(%{"coverage_score" => score}) when is_number(score) do
    {:ok, score |> max(0.0) |> min(1.0) |> Float.round(3)}
  end

  defp fetch_score(_), do: {:error, :missing_coverage_score}

  defp stringify_notes(json) do
    notes = json["notes"]

    base =
      if is_binary(notes) and notes != "",
        do: notes,
        else: "Completeness estimate generated by AI."

    case json["chapters"] do
      chapters when is_list(chapters) and chapters != [] ->
        n = length(chapters)
        "#{base} (#{n} chapter#{if n == 1, do: "", else: "s"} detected)"

      _ ->
        base
    end
  end

  defp broadcast(%UploadedMaterial{course_id: nil}), do: :ok

  defp broadcast(%UploadedMaterial{course_id: course_id, id: material_id}) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update, %{textbook_completeness_checked: material_id}}
    )
  end

  defp format_reason({:assistant_not_found, name}),
    do: "assistant '#{name}' is not configured on Interactor"

  defp format_reason(:timeout), do: "the AI request timed out"
  defp format_reason(other), do: inspect(other)
end
