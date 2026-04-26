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

  # `unique` stops the thundering herd we saw in prod on 2026-04-22: a single
  # course had 11+ concurrent generation jobs running, each pulling all OCR
  # material text and holding a DB connection, which starved the Postgrex pool
  # and blocked validator/classifier jobs from ever making progress. Every
  # "Try again" click on the assessment + each Oban retry previously stacked a
  # new job. Now a duplicate enqueue with the same args is deduped for 5 min
  # across all non-terminal states.
  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [
      period: 300,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias FunSheep.{Courses, Content, Learning, Progress, Repo}
  alias FunSheep.Progress.Event, as: ProgressEvent
  alias FunSheep.Questions
  alias FunSheep.Questions.Question

  # Phases we broadcast for a single-chapter regeneration job. See
  # `.claude/rules/i/progress-feedback.md` — users must always be able to tell
  # which step is running and how many remain.
  @regeneration_phase_total 3

  @system_prompt "You are an expert educational question writer. Generate practice questions based on the subject, grade, and instructions provided. Always return ONLY a valid JSON array of question objects — no prose, no markdown fences."

  # Minimum questions per chapter after initial generation. Chapters below this
  # get a targeted top-off job enqueued before the course moves to "validating".
  @min_questions_per_chapter 15

  @llm_opts %{
    model: "gpt-4o-mini",
    max_tokens: 4_000,
    temperature: 0.7,
    source: "ai_question_generation_worker"
  }

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
    with :ok <- FunSheep.FeatureFlags.require!(:ai_question_generation_enabled) do
      do_perform(args)
    else
      {:cancel, reason} ->
        require Logger
        Logger.info("[AIGen] Skipped (#{reason})")
        {:cancel, reason}
    end
  end

  defp do_perform(args) do
    course_id = args["course_id"]
    chapter_id = args["chapter_id"]
    count = args["count"] || 10
    mode = args["mode"] || "from_material"
    difficulty = args["difficulty"]
    section_name = args["section_name"]

    Logger.info(
      "[AIGen] Generating #{count} questions for course #{course_id}, mode=#{mode}" <>
        if(section_name, do: ", section=\"#{section_name}\"", else: "")
    )

    course = Courses.get_course_with_chapters!(course_id)

    if course.processing_status == "cancelled" do
      Logger.info("[AIGen] Skipped cancelled course #{course_id}")
      :ok
    else
      # For curriculum mode without a specific chapter, fan out one job per
      # chapter so large courses (20+ chapters) don't exhaust a single Oban
      # job's execution window. Each chapter job runs independently, retries
      # independently, and calls finalize_course when it completes.
      if mode == "from_curriculum" and is_nil(chapter_id) and course.chapters != [] do
        chapter_count = length(course.chapters)
        # Each chapter gets at least @min_questions_per_chapter + 5 so the
        # top-off check rarely needs to fire. The div(count, chapter_count)
        # path lets callers request more if they want, but the floor is the
        # minimum + buffer.
        per_chapter = max(div(count, chapter_count), @min_questions_per_chapter + 5)

        Logger.info(
          "[AIGen] Fanning out #{chapter_count} per-chapter jobs (#{per_chapter} each) for course #{course_id}"
        )

        broadcast(course_id, %{
          sub_step: "Generating questions for #{chapter_count} chapters..."
        })

        Enum.each(course.chapters, fn ch ->
          __MODULE__.enqueue(course_id, chapter_id: ch.id, count: per_chapter, mode: mode)
        end)

        Courses.update_course(
          Courses.get_course!(course_id),
          %{
            processing_status: "generating",
            processing_step: "Generating questions for #{chapter_count} chapters..."
          }
        )

        :ok
      else
        chapter = if chapter_id, do: Courses.get_chapter!(chapter_id)
        progress_event = regeneration_base_event(course_id, chapter, count)

        progress_event = maybe_phase(progress_event, :preparing, "Preparing chapter context", 1)
        context = build_context(course, chapter, args)
        prompt = build_prompt(mode, course, chapter, context, count, difficulty, section_name)

        progress_event =
          maybe_phase(progress_event, :generating, "Generating questions with AI", 2)

        case send_to_ai(prompt, course, chapter) do
          {:ok, questions} ->
            progress_event = maybe_phase(progress_event, :saving, "Saving questions", 3)

            inserted =
              insert_questions(questions, course, chapter, context[:figures] || [],
                progress: progress_event,
                mode: mode,
                grounding_material_ids: context[:grounding_material_ids] || []
              )

            Logger.info(
              "[AIGen] Inserted #{inserted} AI-generated questions for course #{course_id}"
            )

            if progress_event, do: Progress.succeeded(progress_event, "questions", inserted)

            # After from_curriculum per-chapter generation, top off the chapter
            # if AI rejections left it below the minimum. Skip for top-off jobs
            # themselves (args["top_off"] == true) to prevent infinite loops.
            if mode == "from_curriculum" and chapter and not args["top_off"] do
              maybe_top_off_chapter(course_id, chapter, mode)
            end

            finalize_course(course_id, inserted)
            :ok

          {:error, reason} ->
            Logger.error("[AIGen] Failed to generate questions: #{inspect(reason)}")

            if progress_event do
              Progress.failed(
                progress_event,
                :ai_unavailable,
                "AI service unavailable — please try again."
              )
            end

            # Still finalize so the course doesn't stay stuck in "generating"
            finalize_course(course_id, 0)
            {:error, reason}
        end
      end
    end
  end

  defp maybe_phase(nil, _phase, _label, _index), do: nil

  defp maybe_phase(%ProgressEvent{} = e, phase, label, index),
    do: Progress.phase(e, phase, label, index)

  # Build a base progress event for a single-chapter regeneration job. Returns
  # nil when there is no chapter (legacy course-wide path), so the caller can
  # short-circuit.
  defp regeneration_base_event(_course_id, nil, _count), do: nil

  defp regeneration_base_event(course_id, chapter, count) do
    ProgressEvent.new(
      job_id: "chapter:#{chapter.id}",
      topic_type: :course,
      topic_id: course_id,
      scope: :question_regeneration,
      phase_total: @regeneration_phase_total,
      subject_id: chapter.id,
      subject_label: chapter.name,
      detail: "#{count} questions for #{chapter.name}"
    )
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
      # Concept-level targeting: when section_id + section_name are set,
      # the prompt focuses exclusively on that concept so generated questions
      # are guaranteed to cover it. The classifier will assign section_id
      # after insertion, but the generation prompt is already scoped.
      |> maybe_put(:section_id, opts[:section_id])
      |> maybe_put(:section_name, opts[:section_name])
      # Difficulty-targeted generation: produces questions at exactly this
      # level to re-fill a depleted {section, difficulty} bucket.
      |> maybe_put(:difficulty, opts[:difficulty])
      # Internal flag: marks a top-off job so it doesn't recursively enqueue
      # another top-off if it also ends up generating fewer questions than
      # ideal (avoids infinite loop).
      |> maybe_put(:top_off, opts[:top_off])

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Build context from OCR materials and existing questions
  defp build_context(course, chapter, args) do
    mode = args["mode"] || "from_material"

    {material_text, material_ids} =
      case mode do
        "from_web_context" ->
          collect_web_context_text(course.id)

        _ ->
          collect_material_text_with_refs(course.id, args["source_material_id"])
      end

    existing_questions =
      if chapter do
        Questions.list_questions_by_chapter(chapter.id)
      else
        Questions.list_questions_by_course(course.id)
      end
      |> Enum.take(20)
      |> Enum.map(& &1.content)

    figures = collect_figures(course.id, args["source_material_id"])

    hobbies = student_hobbies_for_course(course, args["user_role_id"])

    %{
      material_text: material_text |> String.slice(0, 8000),
      existing_questions: existing_questions,
      chapter_names: Enum.map(course.chapters, & &1.name),
      figures: figures,
      hobbies: hobbies,
      grounding_material_ids: material_ids
    }
  end

  # Collect scraped text from discovered web sources as generation context.
  # Returns {"combined text", []} — no material_ids since these are URLs, not
  # uploaded materials. The web source URLs are stored in grounding_refs by
  # the caller on each inserted question.
  defp collect_web_context_text(course_id) do
    sources = Content.list_sources_with_scraped_text(course_id)

    if sources == [] do
      {"", []}
    else
      text =
        sources
        |> Enum.map(fn s ->
          header = "--- #{s.source_type}: #{s.title} ---"
          "#{header}\n#{s.scraped_text}"
        end)
        |> Enum.join("\n\n")

      {text, []}
    end
  end

  defp student_hobbies_for_course(course, explicit_user_role_id) do
    user_role_id = explicit_user_role_id || Map.get(course, :created_by_id)

    case user_role_id do
      nil -> []
      id -> Learning.hobby_names_for_user(id)
    end
  end

  # Gather available SourceFigures for the course so the generator can
  # reference real visuals instead of hallucinating "Table 3". Cap at 30 to
  # keep the prompt tokens manageable.
  defp collect_figures(course_id, specific_material_id) do
    base =
      if specific_material_id do
        Content.list_figures_by_material(specific_material_id)
      else
        Content.list_figures_by_course(course_id)
      end

    Enum.take(base, 30)
  end

  # Phase 4: return both the text AND the material IDs that produced it,
  # so the generator can persist them as `grounding_refs` on each
  # inserted question. Without this, `generation_mode` and
  # `grounding_refs` were NULL on 100% of AI-generated rows in the
  # April audit — admin had no way to trace which materials fed which
  # generated questions.
  defp collect_material_text_with_refs(course_id, specific_material_id) do
    materials =
      if specific_material_id do
        [Content.get_uploaded_material!(specific_material_id)]
      else
        Content.list_materials_by_course(course_id)
        |> Enum.filter(&(&1.ocr_status == :completed))
        # Phase 2 routing: only feed knowledge-classified or mixed
        # materials as grounding. Answer-key / unusable classifications
        # are explicitly excluded so the generator never grounds on an
        # answer sheet.
        |> Enum.filter(fn m ->
          FunSheep.Workers.MaterialClassificationWorker.route(m) in [
            :ground,
            :extract_and_ground
          ]
        end)
      end

    material_ids = Enum.map(materials, & &1.id)

    if material_ids == [] do
      {"", []}
    else
      text =
        from(p in Content.OcrPage,
          where: p.material_id in ^material_ids,
          order_by: [asc: p.material_id, asc: p.page_number],
          select: p.extracted_text
        )
        |> Repo.all()
        |> Enum.join("\n\n")

      {text, material_ids}
    end
  end

  # Header clause declares the default so subsequent specific clauses don't trigger
  # the "default arg in multi-clause function" compiler warning.
  defp build_prompt(mode, course, chapter, context, count, difficulty, section_name \\ nil)

  # Metadata-driven prompt — dispatched when the course has
  # generation_config in its metadata. Works for any standardized test
  # course (ACT, GRE, HSC, etc.) that was created via CourseBuilder.
  # The prompt_context is prepended to give the LLM precise format rules.
  defp build_prompt(
         _mode,
         %{metadata: %{"generation_config" => gen_config}} = course,
         chapter,
         context,
         count,
         difficulty,
         section_name
       )
       when is_map(gen_config) do
    chapter_name = if chapter, do: chapter.name, else: "all chapters"
    topic = section_name || chapter_name
    prompt_context = gen_config["prompt_context"] || ""
    validation_rules = gen_config["validation_rules"] || %{}
    option_count = Map.get(validation_rules, "mcq_option_count", 4)
    answer_labels = Map.get(validation_rules, "answer_labels", ["A", "B", "C", "D"])
    labels_str = Enum.join(answer_labels, ", ")
    correct_label_range = "#{List.first(answer_labels)}–#{List.last(answer_labels)}"

    difficulty_note =
      case difficulty do
        nil -> "Mix of easy (30%), medium (40%), and hard (30%)."
        d -> "#{d} — target this difficulty exclusively."
      end

    material_section =
      if context[:material_text] && context.material_text != "" do
        """
        Reference material:
        ---
        #{context.material_text}
        ---

        """
      else
        ""
      end

    """
    #{prompt_context}
    Domain: #{chapter_name}
    Skill: #{topic}

    FORMAT RULES (follow exactly):
    - Every MCQ question MUST have exactly #{option_count} answer options labelled #{labels_str}.
    - Exactly one option is correct. The others are plausible distractors.
    - Do NOT write ambiguous or subjective questions.
    - Do NOT reference external context not provided in the question stem.

    DIFFICULTY: #{difficulty_note}

    #{material_section}Generate #{count} practice questions for the skill "#{topic}" in the domain "#{chapter_name}".

    IMPORTANT: Return your response as a JSON array of question objects. Each object must have:
    - "content": the question text
    - "answer": the correct answer letter (#{correct_label_range})
    - "question_type": "multiple_choice" for standard MCQ (or "short_answer" for numeric/open response)
    - "options": an object with exactly #{option_count} keys #{inspect(Map.new(answer_labels, fn k -> {k, "..."} end))}
    - "difficulty": one of "easy", "medium", "hard"
    - "explanation": 1–2 sentences explaining why the answer is correct

    Return ONLY the JSON array, no other text.
    """
  end

  # SAT-specific prompt — dispatched before the generic prompt when the
  # course has catalog_test_type "sat" but no generation_config metadata.
  # Enforces Digital SAT format rules: 4-option MCQ for all domains;
  # short passage context for Reading & Writing; numeric-response for
  # Math when appropriate; College Board difficulty tiers.
  defp build_prompt(
         _mode,
         %{catalog_test_type: "sat"} = course,
         chapter,
         context,
         count,
         difficulty,
         section_name
       ) do
    chapter_name = if chapter, do: chapter.name, else: "all chapters"
    topic = section_name || chapter_name

    sat_prompt(
      course.catalog_subject,
      chapter_name,
      topic,
      context,
      count,
      difficulty
    )
  end

  defp build_prompt(mode, course, chapter, context, count, difficulty, section_name) do
    subject = course.subject || course.name
    grade = List.first(course.grades || []) || ""
    chapter_name = if chapter, do: chapter.name, else: "all chapters"

    # When a section (concept) is specified, scope the prompt to that concept.
    # This ensures generated questions test the specific skill/topic rather than
    # spreading across the entire chapter.
    concept_focus =
      if section_name do
        """
        CONCEPT FOCUS — CRITICAL: Every question in this batch MUST test the following
        specific concept only: "#{section_name}"
        Do NOT generate questions about other sections or topics in this chapter.
        The student needs to demonstrate mastery of THIS concept specifically.

        """
      else
        ""
      end

    topic_label = section_name || chapter_name

    base = """
    You are a #{subject} teacher creating questions for grade #{grade} students.
    Topic: #{topic_label}

    """

    difficulty_rubric = """
    DIFFICULTY RUBRIC — apply these criteria to every question, whether multiple choice or short answer:
    - easy: Recall or recognise a single fact, definition, or term directly from the material. The answer is stated explicitly or requires no reasoning. The student only needs to remember it.
      MCQ example: "What molecule carries oxygen in red blood cells?" → Haemoglobin.
      Short answer example: "Name the process plants use to make food from sunlight."
    - medium: Apply or explain a concept in a concrete scenario. The student must understand the concept, not just recall it. Requires connecting an idea to a new context, explaining a mechanism, or working through a single logical step.
      MCQ example: "A cell is placed in a solution more concentrated than its cytoplasm. What will happen, and why?" → The cell will lose water by osmosis.
      Short answer example: "Explain why photosynthesis rate increases when light intensity rises, up to a point."
    - hard: Analyse, compare, evaluate, or synthesise across multiple concepts. Requires multi-step reasoning, predicting outcomes from combined factors, evaluating trade-offs, or identifying cause-and-effect chains not stated directly in the material. The answer cannot be found in any single sentence.
      MCQ example: "A plant has been kept in darkness for 48 hours and is suddenly exposed to bright light. How will ATP production in chloroplasts compare to mitochondria over the first 30 minutes, and what limits the rate in each case?"
      Short answer example: "A scientist finds a cell's membrane potential has collapsed. Describe two distinct mechanisms that could cause this and explain how each would disrupt normal cell function."

    Assign difficulty based on the cognitive demand above, not on how obscure the topic is. A hard question on a simple topic outranks an easy question on a complex topic.

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
          Mix question types: multiple choice and short answer.
          Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
          Make questions specific and educational — not vague or trivial.
          """

        "from_web_context" ->
          if context.material_text != "" do
            """
            Generate #{count} NEW questions based on the web resources above.
            These resources were discovered for this #{subject} course — use their content and terminology.
            Mix question types: multiple choice and short answer.
            Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
            """
          else
            """
            Generate #{count} NEW questions based on your knowledge of #{subject} at grade #{grade} level.
            Use the chapter/topic list above to guide what concepts to test.
            Mix question types: multiple choice and short answer.
            Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
            """
          end

        _ ->
          if context.material_text != "" do
            """
            Generate #{count} NEW questions based on the course material above.
            Mix question types: multiple choice and short answer.
            Vary difficulty from easy to hard.
            """
          else
            """
            Generate #{count} NEW questions based on your knowledge of #{subject} at grade #{grade} level.
            Use the chapter/topic list above to guide what concepts to test.
            Create questions that a #{grade} grade student studying #{subject} would need to know.
            Mix question types: multiple choice and short answer.
            Vary difficulty: roughly 30% easy, 40% medium, 30% hard.
            Make questions specific and educational — not vague or trivial.
            """
          end
      end

    figures_section = build_figures_section(context[:figures] || [])
    hobby_section = build_hobby_section(context[:hobbies] || [])

    visual_rule =
      if (context[:figures] || []) == [] do
        """

        CRITICAL VISUAL RULE: Do NOT write questions that require the student to
        look at a table, figure, graph, chart, diagram, or image. You have no
        figures attached to this generation. Writing "based on the table above"
        or "according to figure 3" when no such figure is shown to the student
        is forbidden — it produces broken, misleading questions.

        Write only questions that can be answered from the text context alone.
        """
      else
        """

        FIGURES AVAILABLE: You have been given #{length(context[:figures])} figure(s)
        above. If a question depends on a visual, set "figure_ids" to an array of
        the relevant figure IDs from the list. Never reference a figure_id that
        is not in the provided list. Never describe a table/figure/graph in the
        question text without also attaching its figure_id.
        """
      end

    format = """

    IMPORTANT: Return your response as a JSON array of question objects. Each object must have:
    - "content": the question text
    - "answer": the correct answer (for MCQ use the letter like "A")
    - "question_type": one of "multiple_choice", "short_answer" (use "true_false" only if the question is genuinely a true/false statement and the test format explicitly uses T/F questions)
    - "options": for multiple_choice, an object like {"A": "...", "B": "...", "C": "...", "D": "..."}
    - "difficulty": one of "easy", "medium", "hard" — assign based on the DIFFICULTY RUBRIC above
    - "explanation": REQUIRED — 1–2 sentences explaining why the answer is correct, citing the concept or mechanism. Questions without a non-empty explanation will be rejected at insert time and never reach students (Phase 4 quality gate).
    - "figure_ids": (optional) array of figure IDs from the FIGURES AVAILABLE list, when the question depends on a visual
    - "table_spec": (optional) JSON table spec when the question requires a table you are inventing. Format: {"headers": [...], "rows": [[...], ...], "caption": "..."}

    Return ONLY the JSON array, no other text.
    """

    # Phase 6 difficulty lock — when the demand-driven loop calls us
    # to re-fill a specific (chapter, difficulty) bucket, force every
    # generated question to the target difficulty so the mix
    # instructions elsewhere in the prompt don't dilute it.
    difficulty_lock =
      case difficulty do
        nil ->
          ""

        d when d in ["easy", "medium", "hard"] or d in [:easy, :medium, :hard] ->
          """
          CRITICAL — DIFFICULTY LOCK: Every question in this batch MUST have
          difficulty="#{d}". Do NOT vary the difficulty. The student has
          exhausted the supply of #{d}-level questions for this chapter and
          needs more at that exact level. Refer to the DIFFICULTY RUBRIC above
          and ensure every question matches the cognitive demand described for "#{d}".

          """

        _ ->
          ""
      end

    base <>
      concept_focus <>
      difficulty_rubric <>
      chapters_section <>
      material_section <>
      figures_section <>
      hobby_section <>
      existing_section <>
      instructions <>
      visual_rule <>
      difficulty_lock <>
      format
  end

  defp build_hobby_section([]), do: ""

  defp build_hobby_section(hobbies) do
    """
    STUDENT'S HOBBIES / INTERESTS: #{Enum.join(hobbies, ", ")}

    When a hobby framing illuminates the concept, use it — e.g. KPOP ->
    follower counts, soccer -> match stats, video games -> XP/levels.
    When you do weave a hobby into a question, set `hobby_context` in the
    JSON to a short note explaining which hobby and how.

    If a hobby framing would feel forced, write a plain question and omit
    `hobby_context`. A forced reference is worse than none.

    """
  end

  defp build_figures_section([]), do: ""

  defp build_figures_section(figures) do
    lines =
      Enum.map_join(figures, "\n", fn f ->
        "- id=#{f.id} | type=#{f.figure_type} | page=#{f.page_number} | caption: #{f.caption || "(none)"}"
      end)

    """
    FIGURES AVAILABLE FOR REFERENCE (attach by "figure_ids" when a question depends on one):
    #{lines}

    """
  end

  defp send_to_ai(prompt, _course, _chapter) do
    case ai_client().call(@system_prompt, prompt, @llm_opts) do
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

  defp insert_questions(questions, course, chapter, available_figures, opts) do
    available_figure_ids = MapSet.new(available_figures, & &1.id)
    progress_event = opts[:progress]
    total = length(questions)
    mode = opts[:mode] || "from_material"
    grounding_material_ids = opts[:grounding_material_ids] || []

    # Phase 4: Pre-computed grounding_refs for every question generated
    # in this batch. All questions from a given call share the same
    # grounding (same prompt, same context), so we build the list once.
    grounding_refs = build_grounding_refs(grounding_material_ids)

    {count, inserted_ids} =
      questions
      |> Enum.with_index(1)
      |> Enum.reduce({0, []}, fn {q_data, idx}, {count, ids} ->
        claimed_figure_ids = sanitize_figure_ids(q_data["figure_ids"], available_figure_ids)
        table_spec = sanitize_table_spec(q_data["table_spec"])
        has_visual = claimed_figure_ids != [] or table_spec != nil

        new_state =
          cond do
            # Phase 4: Enforce explanation at INSERT time. The April
            # audit found 1,916 of 2,141 needs_review rows were stuck
            # on "missing_explanation" — the validator kept flagging
            # them because the generator never provided one. Block at
            # source rather than let them pile up for human cleanup.
            missing_explanation?(q_data) ->
              Logger.warning(
                "[AIGen] Rejected question (missing explanation): #{String.slice(q_data["content"] || "", 0, 120)}"
              )

              {count, ids}

            true ->
              case validate_figure_dependency(q_data["content"], has_visual) do
                :ok ->
                  attrs = %{
                    content: q_data["content"],
                    answer: q_data["answer"],
                    question_type: normalize_question_type(q_data["question_type"]),
                    options: q_data["options"],
                    difficulty: normalize_difficulty(q_data["difficulty"]),
                    explanation: q_data["explanation"],
                    hobby_context: sanitize_hobby_context(q_data["hobby_context"]),
                    is_generated: true,
                    # Phase 1 provenance fields, finally populated on AI
                    # rows (they were NULL on 100% of prod AI rows).
                    source_type: :ai_generated,
                    generation_mode: mode,
                    grounding_refs: grounding_refs,
                    course_id: course.id,
                    chapter_id: if(chapter, do: chapter.id),
                    metadata:
                      %{"source" => "ai_generation", "mode" => mode}
                      |> maybe_put_meta("table_spec", table_spec)
                  }

                  case %Question{} |> Question.changeset(attrs) |> Repo.insert() do
                    {:ok, question} ->
                      attach_figures(question, claimed_figure_ids)
                      {count + 1, [question.id | ids]}

                    {:error, changeset} ->
                      Logger.warning(
                        "[AIGen] Failed to insert question: #{inspect(changeset.errors)}"
                      )

                      {count, ids}
                  end

                {:error, reason} ->
                  Logger.warning(
                    "[AIGen] Rejected question (#{reason}): #{String.slice(q_data["content"] || "", 0, 120)}"
                  )

                  {count, ids}
              end
          end

        if progress_event, do: Progress.tick(progress_event, idx, total, "questions")
        new_state
      end)

    enqueue_validation(inserted_ids, course.id)
    enqueue_classification(inserted_ids)

    count
  end

  # Hand AI-generated questions to the classifier so they pick up a skill
  # tag (section_id) and become adaptive-eligible. See North Star I-1.
  defp enqueue_classification([]), do: :ok

  defp enqueue_classification(ids) do
    FunSheep.Workers.QuestionClassificationWorker.enqueue_for_questions(ids)
  end

  defp enqueue_validation([], _course_id), do: :ok

  defp enqueue_validation(ids, course_id) do
    FunSheep.Workers.QuestionValidationWorker.enqueue(ids, course_id: course_id)
  end

  defp attach_figures(_question, []), do: :ok

  defp attach_figures(question, figure_ids) do
    # Phase 3 wires `FunSheep.Questions.attach_figures/2`. In Phase 1 this list
    # is always empty, so the call never reaches here. The `function_exported?`
    # guard keeps the worker safe if figures are later claimed before Phase 3
    # is deployed.
    if function_exported?(FunSheep.Questions, :attach_figures, 2) do
      FunSheep.Questions.attach_figures(question, figure_ids)
    else
      :ok
    end
  end

  defp sanitize_figure_ids(ids, available) when is_list(ids) do
    ids
    |> Enum.filter(&is_binary/1)
    |> Enum.filter(&MapSet.member?(available, &1))
    |> Enum.uniq()
  end

  defp sanitize_figure_ids(_, _), do: []

  defp sanitize_table_spec(%{"headers" => headers, "rows" => rows} = spec)
       when is_list(headers) and is_list(rows) do
    %{
      "headers" => Enum.map(headers, &to_string/1),
      "rows" => Enum.map(rows, fn row -> Enum.map(row, &to_string/1) end),
      "caption" => (spec["caption"] || "") |> to_string()
    }
  end

  defp sanitize_table_spec(_), do: nil

  # Phase 4 helpers ---------------------------------------------------------

  # Builds the `grounding_refs` jsonb payload shared by every question in
  # a single generation batch. Empty list → `%{}` so the DB default
  # matches unseeded rows.
  defp build_grounding_refs([]), do: %{}

  defp build_grounding_refs(material_ids) when is_list(material_ids) do
    refs =
      Enum.map(material_ids, fn id ->
        %{"type" => "material", "id" => id}
      end)

    %{"refs" => refs}
  end

  # A question with an empty or whitespace-only `explanation` is the
  # exact failure pattern the April audit caught 1,916 times on AP Bio.
  # The validator rejected each of them for missing_explanation. Block
  # at source instead.
  defp missing_explanation?(%{"explanation" => e}) when is_binary(e) do
    String.trim(e) == ""
  end

  defp missing_explanation?(_), do: true

  defp maybe_put_meta(map, _k, nil), do: map
  defp maybe_put_meta(map, k, v), do: Map.put(map, k, v)

  # I-11/I-16: only accept trimmed non-empty strings; everything else -> nil.
  defp sanitize_hobby_context(nil), do: nil
  defp sanitize_hobby_context(""), do: nil

  defp sanitize_hobby_context(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: String.slice(trimmed, 0, 500)
  end

  defp sanitize_hobby_context(_), do: nil

  # Returns :ok when the question is safe to insert, {:error, reason} when it
  # references a visual we cannot render. Catches cases where the LLM writes
  # "based on the table above" without attaching a figure_id or table_spec.
  @figure_reference_pattern ~r/\b(table|figure|fig\.?|graph|chart|diagram|image|shown (above|below)|the picture|the photo|the illustration|depicted|see (the )?(table|figure|graph))\b/i

  @doc false
  def validate_figure_dependency(nil, _has_visual), do: {:error, :empty_content}

  def validate_figure_dependency(content, has_visual) when is_binary(content) do
    if Regex.match?(@figure_reference_pattern, content) and not has_visual do
      {:error, :figure_reference_without_attachment}
    else
      :ok
    end
  end

  defp normalize_question_type("multiple_choice"), do: :multiple_choice
  defp normalize_question_type("true_false"), do: :true_false
  defp normalize_question_type("short_answer"), do: :short_answer
  defp normalize_question_type("free_response"), do: :free_response
  defp normalize_question_type(_), do: :short_answer

  defp normalize_difficulty("easy"), do: :easy
  defp normalize_difficulty("hard"), do: :hard
  defp normalize_difficulty(_), do: :medium

  # Check a single chapter after its per-chapter job completes. If AI
  # rejections left it below @min_questions_per_chapter, enqueue one top-off
  # job (flagged top_off: true so it doesn't recurse).
  defp maybe_top_off_chapter(course_id, chapter, mode) do
    current =
      from(q in Question,
        where:
          q.course_id == ^course_id and
            q.chapter_id == ^chapter.id and
            q.validation_status != :failed,
        select: count(q.id)
      )
      |> Repo.one()
      |> Kernel.||(0)

    if current < @min_questions_per_chapter do
      needed = @min_questions_per_chapter - current + 5

      Logger.info(
        "[AIGen] Top-off '#{String.slice(chapter.name, 0, 50)}': #{current} now, requesting #{needed} more"
      )

      __MODULE__.enqueue(course_id,
        chapter_id: chapter.id,
        count: needed,
        mode: mode,
        top_off: true
      )
    end
  end

  defp broadcast(course_id, data) do
    Phoenix.PubSub.broadcast(FunSheep.PubSub, "course:#{course_id}", {:processing_update, data})
  end

  defp finalize_course(course_id, new_count) do
    course = Courses.get_course!(course_id)
    # Counts passed + needs_review (both are student-visible per @student_visible)
    visible = Questions.count_questions_by_course(course_id)
    pending = Questions.count_pending_by_course(course_id)

    {status, step} =
      cond do
        visible == 0 and pending == 0 ->
          # Truly no questions exist — generation produced nothing at all, and
          # every inserted question failed hard validation.
          # (Do NOT fire this when questions are pending: they were just inserted
          # and haven't been validated yet, so `visible` will be 0 temporarily.)
          Logger.error(
            "[AIGen] Course #{course_id}: AI generation produced 0 questions (#{new_count} new)"
          )

          {"failed",
           "Question generation failed — AI service unavailable. Please try again later."}

        pending == 0 ->
          # No pending questions — all existing questions are already validated.
          if course.processing_status == "ready" do
            {"ready", "#{visible} questions ready"}
          else
            Logger.info(
              "[AIGen] Course #{course_id}: 0 pending after generation (#{new_count} new), marking ready"
            )

            {"ready", "#{visible} questions ready"}
          end

        true ->
          # Pending questions exist — validation worker will flip to ready once done.
          {"validating", "Validating #{pending} generated questions..."}
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
         questions_extracted: visible + pending
       }}
    )
  end

  # --- SAT-specific prompt helpers ---

  @sat_format_json_instruction """

  IMPORTANT: Return your response as a JSON array of question objects. Each object must have:
  - "content": the question stem (and passage when applicable — see format rules below)
  - "answer": the correct answer letter (always "A", "B", "C", or "D" for SAT MCQ)
  - "question_type": always "multiple_choice" for SAT (use "short_answer" only for Math student-produced response)
  - "options": an object with exactly four keys {"A": "...", "B": "...", "C": "...", "D": "..."}
  - "difficulty": one of "easy", "medium", "hard"
  - "explanation": 1–2 sentences explaining why the answer is correct with reference to the skill tested

  Return ONLY the JSON array, no other text.
  """

  defp sat_prompt("mathematics", chapter_name, topic, context, count, difficulty) do
    difficulty_note = sat_difficulty_note(difficulty)

    material_section =
      if context[:material_text] && context.material_text != "" do
        """
        Reference material:
        ---
        #{context.material_text}
        ---

        """
      else
        ""
      end

    """
    You are an expert Digital SAT Math question writer.
    Domain: #{chapter_name}
    Skill: #{topic}

    DIGITAL SAT MATH FORMAT RULES (follow exactly):
    - Every question MUST have exactly 4 answer options labelled A, B, C, D.
    - Exactly one option is correct. The other three are plausible distractors reflecting common errors.
    - Questions may be conceptual, algebraic, or word-problem style — vary the format.
    - Do NOT include questions that require a graph, figure, or table unless you embed the data directly in the question stem.
    - Do NOT write questions that are subjective, ambiguous, or have more than one defensible correct answer.
    - Do NOT reference external context or material not provided in the question stem.

    DIFFICULTY: #{difficulty_note}

    #{material_section}Generate #{count} Digital SAT Math questions for the skill "#{topic}" in the domain "#{chapter_name}".
    Follow the format rules above. Vary difficulty as instructed.
    #{@sat_format_json_instruction}
    """
  end

  defp sat_prompt("reading_writing", chapter_name, topic, context, count, difficulty) do
    difficulty_note = sat_difficulty_note(difficulty)

    material_section =
      if context[:material_text] && context.material_text != "" do
        """
        Source passages you may adapt (do not copy verbatim):
        ---
        #{context.material_text}
        ---

        """
      else
        ""
      end

    """
    You are an expert Digital SAT Reading & Writing question writer.
    Domain: #{chapter_name}
    Skill: #{topic}

    DIGITAL SAT READING & WRITING FORMAT RULES (follow exactly):
    - Each question is based on a short passage (25–150 words). Write the passage in the "content" field BEFORE the question stem, separated by a blank line.
    - Passages should be nonfiction prose: academic, journalistic, or scientific in register.
    - Every question MUST have exactly 4 answer options labelled A, B, C, D.
    - Exactly one option is correct. The other three must be plausible but clearly wrong based on the passage.
    - Do NOT write questions that rely on external knowledge beyond what is stated in the passage.
    - Do NOT write subjective questions or questions with multiple defensible answers.
    - Vary passage topics: science, humanities, social science, literature.

    DIFFICULTY: #{difficulty_note}

    #{material_section}Generate #{count} Digital SAT Reading & Writing questions for the skill "#{topic}" in the domain "#{chapter_name}".
    Follow the format rules above.
    #{@sat_format_json_instruction}
    """
  end

  defp sat_prompt(_catalog_subject, chapter_name, topic, context, count, difficulty) do
    difficulty_note = sat_difficulty_note(difficulty)

    material_section =
      if context[:material_text] && context.material_text != "" do
        """
        Reference material:
        ---
        #{context.material_text}
        ---

        """
      else
        ""
      end

    """
    You are an expert Digital SAT question writer.
    Domain: #{chapter_name}
    Skill: #{topic}

    Generate #{count} Digital SAT practice questions for "#{topic}".
    DIFFICULTY: #{difficulty_note}

    #{material_section}Each question must have exactly 4 options (A–D) with one correct answer.
    Do not write ambiguous or subjective questions.
    #{@sat_format_json_instruction}
    """
  end

  defp sat_difficulty_note(nil), do: "Mix of easy (30%), medium (40%), and hard (30%)."

  defp sat_difficulty_note("easy"),
    do:
      "easy — SAT Module 1 baseline level. Recall or direct application of a single rule or formula."

  defp sat_difficulty_note("medium"),
    do:
      "medium — SAT Module 1/2 mid-range. Apply a concept in a concrete context, one or two logical steps."

  defp sat_difficulty_note("hard"),
    do:
      "hard — SAT Module 2 hardest tier. Multi-step reasoning, synthesis across sub-skills, non-obvious setup."

  defp sat_difficulty_note(d), do: d

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)
end
