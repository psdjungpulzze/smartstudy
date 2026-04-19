defmodule FunSheep.Workers.AIQuestionGenerationWorker do
  @moduledoc """
  Oban worker that generates questions using the Interactor AI agent.

  This is the core of the "infinite questions" feature. It generates:
  1. New questions from OCR'd course material
  2. Variations of existing questions
  3. Questions at specific difficulty levels to fill gaps

  The AI agent receives the course context (subject, grade, chapter topics,
  OCR text) and returns structured questions that get inserted into the
  question bank.

  Triggered by:
  - Post-OCR processing (after materials are extracted)
  - When the adaptive engine exhausts available questions for a topic
  - Manual "generate more" request from the user
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias FunSheep.{Courses, Content, Repo}
  alias FunSheep.Questions
  alias FunSheep.Questions.Question
  alias FunSheep.Interactor.Agents

  import Ecto.Query
  require Logger

  @doc """
  Args:
  - course_id: the course to generate questions for
  - chapter_id: (optional) specific chapter to target
  - count: number of questions to generate (default 10)
  - mode: "from_material" | "variations" | "fill_gaps"
  - source_material_id: (optional) specific material to use as source
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    course_id = args["course_id"]
    chapter_id = args["chapter_id"]
    count = args["count"] || 10
    mode = args["mode"] || "from_material"

    Logger.info("[AIGen] Generating #{count} questions for course #{course_id}, mode=#{mode}")

    course = Courses.get_course_with_chapters!(course_id)

    # For curriculum mode without a specific chapter, generate per-chapter
    # so questions get properly tagged to their topic
    if mode == "from_curriculum" and is_nil(chapter_id) and course.chapters != [] do
      per_chapter = max(div(count, length(course.chapters)), 3)
      chapter_count = length(course.chapters)

      total_inserted =
        course.chapters
        |> Enum.with_index(1)
        |> Enum.reduce(0, fn {ch, idx}, acc ->
          broadcast(course_id, %{
            sub_step: "Generating questions for chapter #{idx}/#{chapter_count}: #{String.slice(ch.name, 0, 40)}..."
          })

          context = build_context(course, ch, args)
          prompt = build_prompt(mode, course, ch, context, per_chapter)

          case send_to_ai(prompt, course, ch) do
            {:ok, questions} ->
              inserted = insert_questions(questions, course, ch)
              broadcast(course_id, %{
                sub_step: "Created #{inserted} questions for #{String.slice(ch.name, 0, 40)}"
              })
              acc + inserted

            {:error, _reason} ->
              acc
          end
        end)

      Logger.info(
        "[AIGen] Inserted #{total_inserted} curriculum questions across #{length(course.chapters)} chapters"
      )

      finalize_course(course_id, total_inserted)
      :ok
    else
      chapter = if chapter_id, do: Courses.get_chapter!(chapter_id)
      context = build_context(course, chapter, args)
      prompt = build_prompt(mode, course, chapter, context, count)

      case send_to_ai(prompt, course, chapter) do
        {:ok, questions} ->
          inserted = insert_questions(questions, course, chapter)

          Logger.info(
            "[AIGen] Inserted #{inserted} AI-generated questions for course #{course_id}"
          )

          finalize_course(course_id, inserted)
          :ok

        {:error, reason} ->
          Logger.error("[AIGen] Failed to generate questions: #{inspect(reason)}")
          # Still finalize so the course doesn't stay stuck in "generating"
          finalize_course(course_id, 0)
          {:error, reason}
      end
    end
  end

  @doc """
  Enqueues a question generation job for a course.
  """
  def enqueue(course_id, opts \\ []) do
    args =
      %{course_id: course_id}
      |> maybe_put(:chapter_id, opts[:chapter_id])
      |> maybe_put(:count, opts[:count])
      |> maybe_put(:mode, opts[:mode])
      |> maybe_put(:source_material_id, opts[:source_material_id])

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Build context from OCR materials and existing questions
  defp build_context(course, chapter, args) do
    material_text = collect_material_text(course.id, args["source_material_id"])

    existing_questions =
      if chapter do
        Questions.list_questions_by_chapter(chapter.id)
      else
        Questions.list_questions_by_course(course.id)
      end
      |> Enum.take(20)
      |> Enum.map(& &1.content)

    %{
      material_text: material_text |> String.slice(0, 8000),
      existing_questions: existing_questions,
      chapter_names: Enum.map(course.chapters, & &1.name)
    }
  end

  defp collect_material_text(course_id, specific_material_id) do
    materials =
      if specific_material_id do
        [Content.get_uploaded_material!(specific_material_id)]
      else
        Content.list_materials_by_course(course_id)
        |> Enum.filter(&(&1.ocr_status == :completed))
      end

    material_ids = Enum.map(materials, & &1.id)

    if material_ids == [] do
      ""
    else
      from(p in Content.OcrPage,
        where: p.material_id in ^material_ids,
        order_by: [asc: p.material_id, asc: p.page_number],
        select: p.extracted_text
      )
      |> Repo.all()
      |> Enum.join("\n\n")
    end
  end

  defp build_prompt(mode, course, chapter, context, count) do
    subject = course.subject || course.name
    grade = course.grade
    chapter_name = if chapter, do: chapter.name, else: "all chapters"

    base = """
    You are a #{subject} teacher creating questions for grade #{grade} students.
    Topic: #{chapter_name}

    """

    material_section =
      if context.material_text != "" do
        """
        Here is the course material to base questions on:
        ---
        #{context.material_text}
        ---

        """
      else
        ""
      end

    existing_section =
      if context.existing_questions != [] do
        """
        Here are some existing questions (create DIFFERENT ones, not duplicates):
        #{Enum.map_join(context.existing_questions, "\n", &"- #{&1}")}

        """
      else
        ""
      end

    # Add chapter listing for curriculum-based generation
    chapters_section =
      if context.chapter_names != [] do
        """
        The course covers these chapters/topics:
        #{Enum.map_join(context.chapter_names, "\n", &"- #{&1}")}

        """
      else
        ""
      end

    instructions =
      case mode do
        "variations" ->
          """
          Generate #{count} VARIATIONS of the existing questions above.
          Change the wording, numbers, or context while testing the same concepts.
          """

        "fill_gaps" ->
          """
          Generate #{count} questions covering topics NOT well-covered by existing questions.
          Focus on gaps in the material coverage.
          """

        "from_curriculum" ->
          """
          Generate #{count} NEW questions based on your knowledge of #{subject} at grade #{grade} level.
          Use the chapter/topic list above to guide what concepts to test.
          Create questions that a #{grade} grade student studying #{subject} would need to know.
          Mix question types: multiple choice, true/false, and short answer.
          Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
          Make questions specific and educational — not vague or trivial.
          """

        _ ->
          if context.material_text != "" do
            """
            Generate #{count} NEW questions based on the course material above.
            Mix question types: multiple choice, true/false, and short answer.
            Vary difficulty from easy to hard.
            """
          else
            """
            Generate #{count} NEW questions based on your knowledge of #{subject} at grade #{grade} level.
            Use the chapter/topic list above to guide what concepts to test.
            Create questions that a #{grade} grade student studying #{subject} would need to know.
            Mix question types: multiple choice, true/false, and short answer.
            Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
            Make questions specific and educational — not vague or trivial.
            """
          end
      end

    format = """

    IMPORTANT: Return your response as a JSON array of question objects. Each object must have:
    - "content": the question text
    - "answer": the correct answer (for MCQ use the letter like "A")
    - "question_type": one of "multiple_choice", "true_false", "short_answer"
    - "options": for multiple_choice, an object like {"A": "...", "B": "...", "C": "...", "D": "..."}
    - "difficulty": one of "easy", "medium", "hard"

    Return ONLY the JSON array, no other text.
    """

    base <> chapters_section <> material_section <> existing_section <> instructions <> format
  end

  defp send_to_ai(prompt, course, _chapter) do
    case Agents.chat("question_gen", prompt, %{
           metadata: %{course_id: course.id, subject: course.subject}
         }) do
      {:ok, response} ->
        parse_ai_response(response)

      {:error, reason} ->
        Logger.error("[AIGen] AI unavailable: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_ai_response(data) when is_binary(data) do
    case extract_json_array(data) do
      {:ok, questions} when is_list(questions) and questions != [] ->
        {:ok, questions}

      {:ok, []} ->
        Logger.error("[AIGen] AI returned empty question list")
        {:error, :empty_response}

      _ ->
        Logger.error("[AIGen] Could not parse AI response as JSON array")
        {:error, :parse_failed}
    end
  end

  defp extract_json_array(text) do
    # Find JSON array in the response (may be wrapped in markdown code blocks)
    cleaned =
      text
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    Jason.decode(cleaned)
  end

  defp insert_questions(questions, course, chapter) do
    Enum.reduce(questions, 0, fn q_data, count ->
      attrs = %{
        content: q_data["content"],
        answer: q_data["answer"],
        question_type: normalize_question_type(q_data["question_type"]),
        options: q_data["options"],
        difficulty: normalize_difficulty(q_data["difficulty"]),
        is_generated: true,
        course_id: course.id,
        chapter_id: if(chapter, do: chapter.id),
        metadata: %{"source" => "ai_generation"}
      }

      case %Question{} |> Question.changeset(attrs) |> Repo.insert() do
        {:ok, _} ->
          count + 1

        {:error, changeset} ->
          Logger.warning("[AIGen] Failed to insert question: #{inspect(changeset.errors)}")
          count
      end
    end)
  end

  defp normalize_question_type("multiple_choice"), do: :multiple_choice
  defp normalize_question_type("true_false"), do: :true_false
  defp normalize_question_type("short_answer"), do: :short_answer
  defp normalize_question_type("free_response"), do: :free_response
  defp normalize_question_type(_), do: :short_answer

  defp normalize_difficulty("easy"), do: :easy
  defp normalize_difficulty("hard"), do: :hard
  defp normalize_difficulty(_), do: :medium

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(FunSheep.PubSub, "course:#{course_id}", {:processing_update, data})
  end

  defp finalize_course(course_id, new_count) do
    course = Courses.get_course!(course_id)
    total = Questions.count_questions_by_course(course_id)

    {status, step} =
      if total > 0 do
        {"ready", "Processing complete! #{total} questions generated."}
      else
        Logger.error("[AIGen] Course #{course_id}: AI generation produced 0 questions (#{new_count} new)")
        {"failed", "Question generation failed — AI service unavailable. Please try again later."}
      end

    Courses.update_course(course, %{
      processing_status: status,
      processing_step: step
    })

    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update,
       %{
         status: status,
         step: step,
         questions_extracted: total
       }}
    )
  end
end
