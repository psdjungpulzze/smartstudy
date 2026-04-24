defmodule FunSheep.Workers.EbookTocImportWorker do
  @moduledoc """
  Oban worker that imports an EPUB's parsed navigation structure as a
  DiscoveredTOC candidate row.

  Takes the TOC entries extracted by EbookExtractWorker and maps them
  into the existing TOCRebase pipeline — exactly like a web-scraped or
  textbook-OCR'd TOC, but with `source_type: "ebook_toc"` and a
  `source_material_id` back-reference.

  If the TOC is empty, logs and exits cleanly — an empty TOC is valid
  (some EPUBs omit navigation) and must not cause the job to fail.

  Job args:
    - `"material_id"` — UUID of the UploadedMaterial (for `source_material_id`)
    - `"course_id"`   — UUID of the Course to attach the TOC to
    - `"toc"`         — list of `%{"title" => ..., "depth" => ..., "href" => ...}`
  """

  use Oban.Worker, queue: :ebook, max_attempts: 3

  alias FunSheep.Courses.{DiscoveredTOC, TOCRebase}
  alias FunSheep.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"material_id" => material_id, "course_id" => course_id, "toc" => toc}
      }) do
    if toc == [] or is_nil(toc) do
      Logger.info("[EbookTocImport] Empty TOC for material=#{material_id}, skipping")
      :ok
    else
      import_toc(material_id, course_id, toc)
    end
  end

  # Tolerate jobs without course_id (material not yet attached to a course)
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    Logger.warning(
      "[EbookTocImport] No course_id in job args for material=#{material_id}, skipping"
    )

    :ok
  end

  defp import_toc(material_id, course_id, toc) when is_list(toc) do
    # Build chapter list from top-level TOC entries (depth == 0).
    # Sections are depth >= 1 entries immediately following their parent.
    chapters = build_chapters(toc)
    chapter_count = length(chapters)

    if chapter_count == 0 do
      Logger.info(
        "[EbookTocImport] No top-level chapters found in TOC for material=#{material_id}"
      )

      :ok
    else
      Logger.info(
        "[EbookTocImport] Proposing #{chapter_count} chapters from EPUB " <>
          "material=#{material_id} course=#{course_id}"
      )

      propose_toc(course_id, material_id, chapters, chapter_count)
    end
  end

  defp propose_toc(course_id, material_id, chapters, chapter_count) do
    # Use "textbook_full" as source — an EPUB TOC is the most authoritative
    # structured form of chapter metadata a textbook can provide.
    %DiscoveredTOC{}
    |> DiscoveredTOC.changeset(%{
      course_id: course_id,
      source: "textbook_full",
      source_type: "ebook_toc",
      source_material_id: material_id,
      chapter_count: chapter_count,
      ocr_char_count: 0,
      chapters: chapters,
      score: TOCRebase.score("textbook_full", chapter_count, 0)
    })
    |> Repo.insert()
    |> case do
      {:ok, toc} ->
        Logger.info("[EbookTocImport] Inserted DiscoveredTOC #{toc.id} for course=#{course_id}")

        :ok

      {:error, changeset} ->
        Logger.error(
          "[EbookTocImport] Failed to insert DiscoveredTOC for course=#{course_id}: " <>
            inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  # ── Chapter structure builder ─────────────────────────────────────────────

  # Convert a flat list of `%{"title" => ..., "depth" => ..., "href" => ...}`
  # into the nested chapter/section structure expected by DiscoveredTOC:
  #
  #   [%{"name" => "Chapter 1: Foo", "sections" => ["1.1 Bar", "1.2 Baz"]}, ...]
  #
  # Top-level (depth 0) entries become chapters. Consecutive deeper entries
  # become sections under the most recent chapter.
  defp build_chapters(toc_entries) do
    {chapters, _last_chapter} =
      Enum.reduce(toc_entries, {[], nil}, fn entry, {chapters, current_chapter} ->
        title = Map.get(entry, "title", "") |> String.trim()
        depth = Map.get(entry, "depth", 0)

        cond do
          title == "" ->
            {chapters, current_chapter}

          depth == 0 ->
            # New top-level chapter
            new_chapter = %{"name" => title, "sections" => []}
            {[new_chapter | chapters], new_chapter}

          current_chapter == nil ->
            # Section before any chapter — promote to top level
            new_chapter = %{"name" => title, "sections" => []}
            {[new_chapter | chapters], new_chapter}

          true ->
            # Section under the current chapter
            updated_chapter =
              Map.update!(current_chapter, "sections", fn sections -> sections ++ [title] end)

            updated_chapters =
              case chapters do
                [_head | tail] -> [updated_chapter | tail]
                [] -> [updated_chapter]
              end

            {updated_chapters, updated_chapter}
        end
      end)

    Enum.reverse(chapters)
  end
end
