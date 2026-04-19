defmodule FunSheep.Workers.MaterialRelevanceWorker do
  @moduledoc """
  Oban worker that validates whether uploaded material matches the course subject/topic.

  Runs after OCR completes for a material. Checks the extracted text against
  the course's subject, grade, and chapter names using keyword matching.

  Results:
  - "relevant": material clearly matches the course
  - "partially_relevant": some overlap but not a strong match
  - "irrelevant": material doesn't appear to match the course
  - "pending": not yet checked

  The relevance score (0.0-1.0) and notes are stored on the material record.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias FunSheep.{Content, Courses, Repo}

  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)

    if is_nil(material.course_id) do
      Logger.info("[Relevance] Material #{material_id} has no course, skipping")
      :ok
    else
      course = Courses.get_course_with_chapters!(material.course_id)
      ocr_text = collect_text(material_id)

      if ocr_text == "" do
        Content.update_uploaded_material(material, %{
          relevance_status: "pending",
          relevance_notes: "No OCR text available yet"
        })

        :ok
      else
        {status, score, notes} = check_relevance(ocr_text, course)

        Content.update_uploaded_material(material, %{
          relevance_status: status,
          relevance_score: score,
          relevance_notes: notes
        })

        if status == "irrelevant" do
          broadcast_warning(material, course, notes)
        end

        Logger.info("[Relevance] Material #{material_id}: #{status} (#{score})")
        :ok
      end
    end
  end

  @doc """
  Enqueues a relevance check for a material.
  """
  def enqueue(material_id) do
    %{material_id: material_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp collect_text(material_id) do
    from(p in Content.OcrPage,
      where: p.material_id == ^material_id,
      order_by: [asc: p.page_number],
      select: p.extracted_text
    )
    |> Repo.all()
    |> Enum.join(" ")
    |> String.slice(0, 5000)
    |> String.downcase()
  end

  defp check_relevance(text, course) do
    # Build keyword lists from course metadata
    subject_keywords = build_subject_keywords(course.subject)
    chapter_keywords = build_chapter_keywords(course.chapters)
    grade_keywords = build_grade_keywords(course.grade)

    # Score each keyword category
    subject_hits = count_hits(text, subject_keywords)
    chapter_hits = count_hits(text, chapter_keywords)
    grade_hits = count_hits(text, grade_keywords)

    subject_score =
      if length(subject_keywords) > 0, do: subject_hits / length(subject_keywords), else: 0

    chapter_score =
      if length(chapter_keywords) > 0,
        do: min(chapter_hits / max(length(chapter_keywords), 1), 1.0),
        else: 0

    # Weighted score: subject match is most important
    total_score =
      (subject_score * 0.5 + chapter_score * 0.4 + if(grade_hits > 0, do: 0.1, else: 0.0))
      |> Float.round(3)

    {status, notes} =
      cond do
        total_score >= 0.4 ->
          {"relevant",
           "Material matches #{course.subject}. Found #{subject_hits} subject keywords and #{chapter_hits} chapter references."}

        total_score >= 0.15 ->
          {"partially_relevant",
           "Some overlap with #{course.subject} but not a strong match. Consider reviewing this material."}

        true ->
          {"irrelevant",
           "This material doesn't appear to match #{course.subject} (Grade #{course.grade}). " <>
             "It may have been uploaded to the wrong course."}
      end

    {status, total_score, notes}
  end

  defp build_subject_keywords(nil), do: []

  defp build_subject_keywords(subject) do
    base = [String.downcase(subject)]

    # Add common synonyms/related terms per subject
    synonyms =
      case String.downcase(subject) do
        "math" <> _ -> ~w(algebra geometry calculus equation formula theorem proof)
        "science" -> ~w(experiment hypothesis observation data conclusion variable)
        "biology" -> ~w(cell organism dna protein evolution gene species)
        "chemistry" -> ~w(element compound reaction molecule atom periodic)
        "physics" -> ~w(force energy velocity acceleration momentum wave)
        "history" -> ~w(war revolution empire civilization century era)
        "english" -> ~w(grammar essay literature vocabulary writing reading)
        "geography" -> ~w(continent country climate population region terrain)
        _ -> []
      end

    base ++ synonyms
  end

  defp build_chapter_keywords(chapters) do
    chapters
    |> Enum.flat_map(fn ch ->
      ch.name
      |> String.downcase()
      |> String.split(~r/[\s,\-:]+/)
      |> Enum.reject(&(String.length(&1) < 4))
    end)
    |> Enum.uniq()
  end

  defp build_grade_keywords(nil), do: []

  defp build_grade_keywords(grade) do
    ["grade #{String.downcase(grade)}", "#{grade}th grade", "level #{String.downcase(grade)}"]
  end

  defp count_hits(text, keywords) do
    Enum.count(keywords, &String.contains?(text, &1))
  end

  defp broadcast_warning(material, course, notes) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course.id}",
      {:material_relevance_warning,
       %{
         material_id: material.id,
         file_name: material.file_name,
         notes: notes
       }}
    )
  end
end
