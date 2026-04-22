defmodule FunSheep.Workers.CourseDiscoveryWorker do
  @moduledoc """
  Oban worker that discovers chapter/section structure for a course.

  Uses the course metadata (subject, grade, textbook) to identify chapters
  and sections via AI. This runs independently of OCR — a course can have
  its structure discovered even without any uploaded materials.

  After discovery completes, checks if OCR is also done. If both are complete,
  triggers question extraction.
  """

  use Oban.Worker, queue: :ai, max_attempts: 2

  alias FunSheep.{Courses, Repo}
  alias FunSheep.Courses.{Chapter, Section}
  alias FunSheep.Interactor.Agents

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id} = args}) do
    Logger.info("[Discovery] Starting chapter discovery for course #{course_id}")

    course = Courses.get_course_with_chapters!(course_id)
    source_context = args["source_context"] || ""

    Courses.update_course(course, %{
      processing_step: "Discovering course structure..."
    })

    broadcast(course_id, %{status: "discovering", step: "Discovering course structure..."})

    # Use AI to discover chapters based on course metadata + web search results
    chapters = discover_chapters(course, source_context)

    Logger.info("[Discovery] Found #{length(chapters)} chapters for course #{course_id}")

    if chapters == [] do
      Logger.error("[Discovery] No chapters discovered for course #{course_id} — AI unavailable")

      Courses.update_course(course, %{
        processing_status: "failed",
        processing_step:
          "Chapter discovery failed — AI service unavailable. Please try again later."
      })

      broadcast(course_id, %{
        status: "failed",
        step: "Chapter discovery failed — AI service unavailable. Please try again later."
      })

      :ok
    else
      # Create chapters (and sections if discovered) in DB
      broadcast(course_id, %{sub_step: "Creating #{length(chapters)} chapters in database..."})
      created_count = create_chapters(chapters, course_id)

      Courses.update_course(course, %{
        processing_step: "Discovered #{created_count} chapters"
      })

      # Mark discovery as complete in metadata
      mark_discovery_complete(course_id)

      # Check if we can proceed to question extraction
      maybe_trigger_extraction(course_id)

      :ok
    end
  end

  defp discover_chapters(course, source_context) do
    textbook_name = get_textbook_name(course)
    subject = course.subject
    grade = course.grade

    broadcast(course.id, %{
      sub_step: "Building curriculum analysis for #{subject} (Grade #{grade})..."
    })

    prompt = build_discovery_prompt(subject, grade, textbook_name, source_context)

    broadcast(course.id, %{sub_step: "Asking AI to identify chapters and sections..."})

    case Agents.chat("course_discovery", prompt, %{
           source: "course_discovery_worker",
           metadata: %{course_id: course.id, subject: subject, grade: grade}
         }) do
      {:ok, response} ->
        case parse_chapters_json(response) do
          {:ok, chapters} ->
            broadcast(course.id, %{
              sub_step: "AI returned #{length(chapters)} chapters, processing..."
            })

            chapters

          {:error, reason} ->
            Logger.error(
              "[Discovery] Failed to parse AI response for course #{course.id}: #{inspect(reason)}"
            )

            broadcast(course.id, %{sub_step: "AI returned invalid format, retrying..."})
            []
        end

      {:error, reason} ->
        Logger.error(
          "[Discovery] AI discovery failed for course #{course.id}: #{inspect(reason)}"
        )

        broadcast(course.id, %{sub_step: "AI request failed: #{inspect(reason)}"})
        []
    end
  end

  defp get_textbook_name(course) do
    cond do
      course.custom_textbook_name && course.custom_textbook_name != "" ->
        course.custom_textbook_name

      course.textbook_id ->
        textbook = Courses.get_textbook!(course.textbook_id)
        "#{textbook.title}#{if textbook.author, do: " by #{textbook.author}", else: ""}"

      true ->
        nil
    end
  end

  defp build_discovery_prompt(subject, grade, textbook_name, source_context) do
    textbook_context =
      if textbook_name do
        "The textbook being used is: #{textbook_name}. Use the actual chapter structure from this textbook."
      else
        "No specific textbook selected. Use a standard curriculum structure."
      end

    web_context =
      if source_context != "" do
        """

        We've already searched the web and found these relevant study materials and resources for this course:
        #{source_context}

        Use these discovered sources to inform your chapter structure. If the sources reference specific topics,
        units, or chapters, incorporate those into your structure. This helps ensure the chapters align with
        available study materials.
        """
      else
        ""
      end

    """
    You are helping organize a study course. Identify the chapters and sections for this course.

    Subject: #{subject}
    Grade Level: #{grade}
    #{textbook_context}
    #{web_context}
    Return a JSON array of chapters. Each chapter should have a "name" and optionally "sections" (array of section names).

    Example format:
    [
      {"name": "Chapter 1: Introduction to Biology", "sections": ["1.1 What is Biology?", "1.2 The Scientific Method"]},
      {"name": "Chapter 2: Cell Structure", "sections": ["2.1 Cell Theory", "2.2 Organelles"]}
    ]

    Return ONLY the JSON array, no other text.

    Include every chapter that's standard for this subject, grade level, and
    (if given) the specific textbook. Do NOT truncate or summarize — a typical
    textbook has 20–50 chapters, and compressing that into a short list leaves
    students without coverage of large parts of the course.
    """
  end

  defp parse_chapters_json(content) do
    # Try to extract JSON from the response
    json_str =
      case Regex.run(~r/\[[\s\S]*\]/m, content) do
        [match] -> match
        _ -> content
      end

    case Jason.decode(json_str) do
      {:ok, chapters} when is_list(chapters) ->
        parsed =
          Enum.map(chapters, fn ch ->
            %{
              name: ch["name"] || "Unnamed Chapter",
              sections: (ch["sections"] || []) |> Enum.map(&to_string/1)
            }
          end)

        {:ok, parsed}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp create_chapters(chapters, course_id) do
    chapters
    |> Enum.with_index(1)
    |> Enum.map(fn {chapter_data, position} ->
      {:ok, chapter} =
        %Chapter{}
        |> Chapter.changeset(%{name: chapter_data.name, position: position, course_id: course_id})
        |> Repo.insert()

      # Create sections if present
      if chapter_data[:sections] && chapter_data.sections != [] do
        chapter_data.sections
        |> Enum.with_index(1)
        |> Enum.each(fn {section_name, sec_pos} ->
          %Section{}
          |> Section.changeset(%{
            name: section_name,
            position: sec_pos,
            chapter_id: chapter.id
          })
          |> Repo.insert()
        end)
      end

      chapter
    end)
    |> length()
  end

  defp mark_discovery_complete(course_id) do
    course = Courses.get_course!(course_id)
    metadata = Map.merge(course.metadata || %{}, %{"discovery_complete" => true})
    Courses.update_course(course, %{metadata: metadata})
  end

  defp maybe_trigger_extraction(course_id) do
    course = Courses.get_course!(course_id)

    ocr_done = course.ocr_total_count == 0 or course.ocr_completed_count >= course.ocr_total_count

    if ocr_done do
      Logger.info("[Discovery] Discovery + OCR both complete, advancing course #{course_id}")

      Courses.advance_to_extraction(course_id)
    else
      Logger.info(
        "[Discovery] Waiting for OCR — #{course.ocr_completed_count}/#{course.ocr_total_count}"
      )
    end
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(FunSheep.PubSub, "course:#{course_id}", {:processing_update, data})
  end
end
