defmodule FunSheep.Workers.QuestionExtractionWorker do
  @moduledoc """
  Oban worker that extracts questions from OCR'd course materials.

  Scans OCR text for question patterns (numbered questions, multiple choice,
  true/false, etc.) and creates question records linked to chapters.

  This is the final step in the course processing pipeline.
  """

  use Oban.Worker, queue: :ai, max_attempts: 2

  alias FunSheep.{Content, Courses, Repo}
  alias FunSheep.Questions.Question

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"course_id" => course_id}}) do
    Logger.info("[Questions] Starting extraction for course #{course_id}")

    course = Courses.get_course_with_chapters!(course_id)
    ocr_pages = collect_ocr_pages(course_id)

    if ocr_pages == [] do
      Logger.info("[Questions] No OCR pages for course #{course_id}, generating from curriculum")

      # Don't finalize yet — set status to "generating" and let AI worker finalize
      set_generating_status(course, 0)

      # No materials uploaded — generate questions purely from course context
      # (subject, grade, chapter names). This is how we provide questions
      # even when students don't upload any files.
      FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course_id,
        count: 30,
        mode: "from_curriculum"
      )

      :ok
    else
      questions = extract_questions(ocr_pages, course)
      Logger.info("[Questions] Extracted #{length(questions)} questions for course #{course_id}")

      # Insert questions into DB
      inserted =
        Enum.reduce(questions, 0, fn q_attrs, count ->
          # Link to course and source material for question set filtering
          material_id = get_in(q_attrs, [:metadata, "material_id"])

          attrs =
            q_attrs
            |> Map.put(:course_id, course_id)
            |> Map.put(:source_material_id, material_id)

          # Try to match to a chapter
          attrs = maybe_assign_chapter(attrs, course.chapters)

          case %Question{} |> Question.changeset(attrs) |> Repo.insert() do
            {:ok, _} -> count + 1
            {:error, _} -> count
          end
        end)

      # Don't finalize yet — AI generation will add more questions
      set_generating_status(course, inserted)

      # After extracting questions from materials, trigger AI to generate more
      FunSheep.Workers.AIQuestionGenerationWorker.enqueue(course_id,
        count: 20,
        mode: "from_material"
      )

      :ok
    end
  end

  defp set_generating_status(course, extracted_count) do
    step =
      if extracted_count > 0,
        do: "Extracted #{extracted_count} questions, generating more with AI...",
        else: "Generating questions with AI..."

    Courses.update_course(course, %{
      processing_status: "generating",
      processing_step: step
    })

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course.id}",
      {:processing_update,
       %{
         status: "generating",
         step: step,
         questions_extracted: extracted_count
       }}
    )
  end

  # Regex-based question extraction is reliable on sample-question materials
  # (practice tests, past exams, Q&A banks) and noisy on textbook prose.
  # Prefer sample_questions materials; only fall back to textbook-like
  # materials when the user hasn't supplied any question sources.
  @question_kinds [:sample_questions]
  @textbook_fallback_kinds [:textbook, :supplementary_book]

  defp collect_ocr_pages(course_id) do
    materials = Content.list_materials_by_course(course_id)
    completed = Enum.filter(materials, &(&1.ocr_status == :completed))

    question_ids =
      completed
      |> Enum.filter(&(&1.material_kind in @question_kinds))
      |> Enum.map(& &1.id)

    completed_ids =
      if question_ids != [] do
        question_ids
      else
        completed
        |> Enum.filter(&(&1.material_kind in @textbook_fallback_kinds))
        |> Enum.map(& &1.id)
      end

    if completed_ids == [] do
      []
    else
      from(p in Content.OcrPage,
        where: p.material_id in ^completed_ids,
        order_by: [asc: p.material_id, asc: p.page_number],
        preload: [:material]
      )
      |> Repo.all()
    end
  end

  # Pattern-based question extraction from OCR text.
  # Looks for numbered questions, multiple choice patterns, etc.
  defp extract_questions(ocr_pages, _course) do
    ocr_pages
    |> Enum.flat_map(fn page ->
      text = page.extracted_text || ""
      source_page = page.page_number

      questions = []

      # Pattern 1: Numbered questions with answers
      # "1. What is biology? Answer: Biology is the study of life."
      questions =
        questions ++
          (Regex.scan(~r/(\d+)\.\s+(.+?)\s*(?:Answer|Ans|A)[:\.]?\s*(.+?)(?=\n\d+\.|\z)/ms, text)
           |> Enum.map(fn [_full, _num, content, answer] ->
             %{
               content: String.trim(content),
               answer: String.trim(answer),
               question_type: :short_answer,
               difficulty: :medium,
               source_page: source_page,
               is_generated: false,
               metadata: %{"source" => "ocr_extraction", "material_id" => page.material_id}
             }
           end))

      # Pattern 2: Multiple choice (A/B/C/D)
      mc_pattern =
        ~r/(\d+)\.\s+(.+?)\n\s*[Aa][.)]\s*(.+?)\n\s*[Bb][.)]\s*(.+?)\n\s*[Cc][.)]\s*(.+?)\n\s*[Dd][.)]\s*(.+?)(?:\n|$)/ms

      questions =
        questions ++
          (Regex.scan(mc_pattern, text)
           |> Enum.map(fn [_full, _num, question, a, b, c, d] ->
             %{
               content: String.trim(question),
               answer: "",
               question_type: :multiple_choice,
               options: %{
                 "A" => String.trim(a),
                 "B" => String.trim(b),
                 "C" => String.trim(c),
                 "D" => String.trim(d)
               },
               difficulty: :medium,
               source_page: source_page,
               is_generated: false,
               metadata: %{"source" => "ocr_extraction", "material_id" => page.material_id}
             }
           end))

      # Pattern 3: True/False questions
      questions =
        questions ++
          (Regex.scan(~r/(\d+)\.\s+(.+?)\s*\(?\s*(True|False|T|F)\s*\)?/mi, text)
           |> Enum.map(fn [_full, _num, content, answer] ->
             %{
               content: String.trim(content),
               answer: normalize_tf(answer),
               question_type: :true_false,
               difficulty: :easy,
               source_page: source_page,
               is_generated: false,
               metadata: %{"source" => "ocr_extraction", "material_id" => page.material_id}
             }
           end))

      # Pattern 4: "Question:" prefix pattern
      questions =
        questions ++
          (Regex.scan(
             ~r/Question\s*\d*\s*[:\.]?\s*(.+?)\s*Answer\s*[:\.]?\s*(.+?)(?=Question|\z)/ms,
             text
           )
           |> Enum.map(fn [_full, content, answer] ->
             %{
               content: String.trim(content),
               answer: String.trim(answer),
               question_type: :short_answer,
               difficulty: :medium,
               source_page: source_page,
               is_generated: false,
               metadata: %{"source" => "ocr_extraction", "material_id" => page.material_id}
             }
           end))

      questions
    end)
    |> Enum.reject(fn q -> String.length(q.content) < 10 end)
    |> Enum.uniq_by(& &1.content)
  end

  defp normalize_tf(val) do
    case String.downcase(String.trim(val)) do
      v when v in ["true", "t"] -> "True"
      _ -> "False"
    end
  end

  # Try to assign a chapter based on the question's source material filename
  defp maybe_assign_chapter(attrs, chapters) when chapters == [], do: attrs

  defp maybe_assign_chapter(attrs, chapters) do
    material_id = get_in(attrs, [:metadata, "material_id"])

    if material_id do
      material = Content.get_uploaded_material!(material_id)

      matched =
        Enum.find(chapters, fn ch ->
          # Match chapter number in filename to chapter name
          case Regex.run(~r/Chapter\s*(\d+)/i, material.file_name || "") do
            [_, num] -> String.contains?(ch.name, num)
            _ -> false
          end
        end)

      if matched do
        Map.put(attrs, :chapter_id, matched.id)
      else
        attrs
      end
    else
      attrs
    end
  end
end
