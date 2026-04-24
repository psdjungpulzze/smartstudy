defmodule FunSheep.Courses do
  @moduledoc """
  The Courses context.

  Manages courses, chapters, and sections. Links courses to schools
  for per-school question filtering.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Courses.{Course, Chapter, Section, Textbook}

  ## Courses

  def list_courses do
    Repo.all(Course)
  end

  def get_course!(id), do: Repo.get!(Course, id)

  @doc """
  Admin-facing paginated course list. Preloads school and creator
  (user_role). Supports optional `:search` on name/subject.
  """
  def list_courses_for_admin(opts \\ []) do
    opts
    |> admin_courses_query()
    |> order_by([c], desc: c.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 25))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload([:school, :created_by])
    |> Repo.all()
  end

  @doc "Counts courses matching the same filters used by `list_courses_for_admin/1`."
  def count_courses_for_admin(opts \\ []) do
    opts
    |> admin_courses_query()
    |> select([c], count(c.id))
    |> Repo.one()
  end

  defp admin_courses_query(opts) do
    search = Keyword.get(opts, :search)
    query = from(c in Course)

    case search do
      nil ->
        query

      "" ->
        query

      term when is_binary(term) ->
        pattern = "%#{term}%"
        from(c in query, where: ilike(c.name, ^pattern) or ilike(c.subject, ^pattern))
    end
  end

  @doc """
  Gets a course with chapters and sections preloaded, ordered by position.
  """
  def get_course_with_chapters!(id) do
    sections_query = from(s in Section, order_by: s.position)

    chapters_query =
      from(c in Chapter, order_by: c.position, preload: [sections: ^sections_query])

    Course
    |> Repo.get!(id)
    |> Repo.preload([:school, chapters: chapters_query])
  end

  @doc """
  Searches courses by subject, grade, and/or school_id.
  Returns matching courses with school preloaded.
  """
  def search_courses(params) when is_map(params) do
    Course
    |> maybe_filter_subject(params)
    |> maybe_filter_grade(params)
    |> maybe_filter_school(params)
    |> order_by([c], asc: c.name)
    |> preload(:school)
    |> Repo.all()
  end

  defp maybe_filter_subject(query, %{"subject" => subject}) when subject != "" do
    where(query, [c], ilike(c.subject, ^"%#{subject}%") or ilike(c.name, ^"%#{subject}%"))
  end

  defp maybe_filter_subject(query, _params), do: query

  defp maybe_filter_grade(query, %{"grade" => grade}) when grade != "" do
    where(query, [c], c.grade == ^grade)
  end

  defp maybe_filter_grade(query, _params), do: query

  defp maybe_filter_school(query, %{"school_id" => school_id}) when school_id != "" do
    where(query, [c], c.school_id == ^school_id)
  end

  defp maybe_filter_school(query, _params), do: query

  @grade_order ~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College)

  @doc """
  Lists courses for nearby grades (+-1) at the given school,
  excluding courses the user already owns.
  """
  def list_nearby_courses(school_id, grade, user_role_id) do
    grades = nearby_grades(grade)

    query =
      from(c in Course,
        where: c.grade in ^grades,
        where: c.created_by_id != ^user_role_id,
        order_by: [asc: c.name],
        preload: [:school]
      )

    query =
      if school_id do
        where(query, [c], c.school_id == ^school_id)
      else
        query
      end

    Repo.all(query)
  end

  defp nearby_grades(nil), do: @grade_order

  defp nearby_grades(grade) do
    idx = Enum.find_index(@grade_order, &(&1 == grade))

    if idx do
      lo = max(idx - 1, 0)
      hi = min(idx + 1, length(@grade_order) - 1)
      Enum.slice(@grade_order, lo..hi)
    else
      @grade_order
    end
  end

  @doc """
  Lists courses created by or associated with a user role.
  """
  def list_courses_for_user(nil), do: []

  def list_courses_for_user(user_role_id) do
    from(c in Course,
      where: c.created_by_id == ^user_role_id,
      order_by: [desc: c.inserted_at],
      preload: [:school]
    )
    |> Repo.all()
  end

  @doc """
  Lists courses with chapter and question counts for dashboard display.
  """
  def list_courses_with_stats(user_role_id) do
    from(c in Course,
      where: c.created_by_id == ^user_role_id,
      left_join: ch in assoc(c, :chapters),
      left_join: q in assoc(c, :questions),
      group_by: c.id,
      select: %{
        course: c,
        chapter_count: count(ch.id, :distinct),
        question_count: count(q.id, :distinct)
      },
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists courses the user is "enrolled in" — either created by them or
  has test schedules for. Returns courses with school preloaded.
  """
  def list_user_courses(nil), do: []

  def list_user_courses(user_role_id) do
    from(c in Course,
      left_join: ts in FunSheep.Assessments.TestSchedule,
      on: ts.course_id == c.id and ts.user_role_id == ^user_role_id,
      where: c.created_by_id == ^user_role_id or not is_nil(ts.id),
      distinct: c.id,
      order_by: [desc: c.inserted_at],
      preload: [:school]
    )
    |> Repo.all()
  end

  def create_course(attrs \\ %{}) do
    %Course{}
    |> Course.changeset(attrs)
    |> Repo.insert()
  end

  def update_course(%Course{} = course, attrs) do
    course
    |> Course.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Called by `FunSheep.Workers.QuestionValidationWorker` once every pending
  question for a course has a verdict. Flips the course to "ready" if at
  least one question passed validation, or "failed" if none did.

  This is the honest-failure path: if the validator rejected every generated
  question, the user sees a failed status rather than a course full of bad
  questions marked ready.
  """
  def finalize_after_validation(course_id) do
    alias FunSheep.Questions.Question

    course = get_course!(course_id)

    counts =
      from(q in Question,
        where: q.course_id == ^course_id,
        group_by: q.validation_status,
        select: {q.validation_status, count(q.id)}
      )
      |> Repo.all()
      |> Map.new()

    passed = Map.get(counts, :passed, 0)
    needs_review = Map.get(counts, :needs_review, 0)
    failed = Map.get(counts, :failed, 0)
    pending = Map.get(counts, :pending, 0)

    cond do
      pending > 0 ->
        # Still work to do — shouldn't usually reach here, worker guards it
        {:ok, course}

      passed > 0 ->
        update_course(course, %{
          processing_status: "ready",
          processing_step:
            "Processing complete! #{passed} questions validated and ready." <>
              if(needs_review > 0, do: " (#{needs_review} flagged for review)", else: "")
        })
        |> tap(fn _ ->
          broadcast_finalization(course_id, "ready", passed, needs_review, failed)
        end)

      true ->
        # Distinguish "validator couldn't read its own output" (infrastructure
        # problem — retry is the right action) from "validator looked and
        # rejected everything" (content problem — different materials needed).
        # Honest failure copy beats a fake "still processing" forever.
        unparseable = unparseable_failure_count(course_id)

        copy =
          if unparseable > 0 and unparseable >= div(failed, 2) do
            "Question validation couldn't complete — the validator returned " <>
              "responses we couldn't read. Try regenerating or contact support if it persists."
          else
            "Question validation failed — all generated questions were rejected. " <>
              "Please try again or upload different materials."
          end

        update_course(course, %{
          processing_status: "failed",
          processing_step: copy
        })
        |> tap(fn _ ->
          broadcast_finalization(course_id, "failed", 0, 0, failed)
        end)
    end
  end

  defp unparseable_failure_count(course_id) do
    alias FunSheep.Questions.Question

    from(q in Question,
      where:
        q.course_id == ^course_id and q.validation_status == :failed and
          fragment("?->>'error' = ?", q.validation_report, "validator_unparseable_response")
    )
    |> Repo.aggregate(:count)
  end

  defp broadcast_finalization(course_id, status, passed, needs_review, failed) do
    Phoenix.PubSub.broadcast(
      FunSheep.PubSub,
      "course:#{course_id}",
      {:processing_update,
       %{
         status: status,
         step: "Validation complete",
         questions_extracted: passed,
         questions_needs_review: needs_review,
         questions_failed: failed
       }}
    )

    if status == "ready" do
      %{course_id: course_id}
      |> FunSheep.Workers.CourseReadyEmailWorker.new()
      |> Oban.insert()
    end
  end

  # Called once discovery + OCR are both finished. If the course has any
  # OCR-completed textbook material, run EnrichDiscoveryWorker to replace the
  # generic initial chapters with the real textbook's table of contents.
  # Otherwise go straight to QuestionExtractionWorker. Either way the next
  # worker is responsible for moving the course to "extracting".
  def advance_to_extraction(course_id) do
    alias FunSheep.Content

    textbook_kinds = [:textbook, :supplementary_book]

    has_textbook_ocr? =
      Content.list_materials_by_course_and_kind(course_id, textbook_kinds)
      |> Enum.any?(&(&1.ocr_status == :completed))

    if has_textbook_ocr? do
      %{course_id: course_id}
      |> FunSheep.Workers.EnrichDiscoveryWorker.new()
      |> Oban.insert()
    else
      course = get_course!(course_id)

      update_course(course, %{
        processing_status: "extracting",
        processing_step: "Extracting and generating questions...",
        metadata: Map.merge(course.metadata || %{}, %{"ocr_complete" => true})
      })

      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        "course:#{course_id}",
        {:processing_update,
         %{status: "extracting", step: "Extracting and generating questions..."}}
      )

      %{course_id: course_id}
      |> FunSheep.Workers.QuestionExtractionWorker.new()
      |> Oban.insert()
    end
  end

  def delete_course(%Course{} = course) do
    Repo.delete(course)
  end

  def change_course(%Course{} = course, attrs \\ %{}) do
    Course.changeset(course, attrs)
  end

  @doc """
  Reprocess a course from scratch: delete old chapters, questions, and OCR pages,
  reset material OCR statuses to pending, and re-enqueue the processing pipeline.
  """
  def reprocess_course(course_id) do
    import Ecto.Query

    course = get_course!(course_id)

    # Delete existing questions for this course
    from(q in FunSheep.Questions.Question, where: q.course_id == ^course_id)
    |> Repo.delete_all()

    # Delete existing chapters (sections cascade via DB)
    from(ch in Chapter, where: ch.course_id == ^course_id)
    |> Repo.delete_all()

    # Delete OCR pages for all materials in this course
    material_ids =
      from(m in FunSheep.Content.UploadedMaterial,
        where: m.course_id == ^course_id,
        select: m.id
      )
      |> Repo.all()

    if material_ids != [] do
      from(p in FunSheep.Content.OcrPage, where: p.material_id in ^material_ids)
      |> Repo.delete_all()

      # Reset all materials to pending
      from(m in FunSheep.Content.UploadedMaterial, where: m.course_id == ^course_id)
      |> Repo.update_all(set: [ocr_status: :pending])
    end

    # Reset course processing state and metadata flags
    update_course(course, %{
      processing_status: "processing",
      processing_step: "Reprocessing...",
      ocr_completed_count: 0,
      ocr_total_count: 0,
      metadata:
        Map.merge(course.metadata || %{}, %{
          "discovery_complete" => false,
          "ocr_complete" => false
        })
    })

    # Enqueue the processing pipeline
    %{course_id: course_id}
    |> FunSheep.Workers.ProcessCourseWorker.new()
    |> Oban.insert()

    {:ok, get_course!(course_id)}
  end

  def cancel_processing(course_id) do
    course = get_course!(course_id)

    # Cancel pending Oban jobs for this course
    import Ecto.Query

    from(j in Oban.Job,
      where: j.state in ["available", "scheduled", "retryable"],
      where: fragment("?->>'course_id' = ?", j.args, ^course_id)
    )
    |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

    update_course(course, %{
      processing_status: "cancelled",
      processing_step: "Processing stopped by user"
    })
  end

  @doc """
  Enrich an existing course with newly uploaded materials.

  Unlike `reprocess_course`, this keeps existing questions and only:
  1. OCRs new pending materials
  2. Re-discovers chapters from textbook content
  3. Re-generates questions from combined content
  """
  def enrich_course(course_id) do
    course = get_course!(course_id)

    # Set processing status immediately so the UI shows the progress component
    # before the Oban worker picks up the job (which can take a few seconds).
    {:ok, course} =
      update_course(course, %{
        processing_status: "processing",
        processing_step: "Preparing..."
      })

    %{course_id: course_id}
    |> FunSheep.Workers.EnrichCourseWorker.new()
    |> Oban.insert()

    {:ok, course}
  end

  @completeness_threshold 0.85

  @doc """
  Returns the completeness threshold (0.0–1.0) at which a textbook is
  considered complete.
  """
  def completeness_threshold, do: @completeness_threshold

  @doc """
  Reports the textbook completeness status for a course.

  Inspects the course's uploaded `:textbook` materials and, among those that
  finished OCR, picks the "most complete" one — ranked by
  `completeness_score` first, OCR page count as the tiebreaker. The chosen
  material is returned so the UI can surface its name, score, and notes.

  Statuses:
    * `:missing`    — no textbook uploaded
    * `:processing` — textbook uploaded, OCR not finished
    * `:partial`    — OCR done but completeness score below threshold
                      (or `ocr_status == :partial`)
    * `:complete`   — OCR done and completeness score ≥ threshold
                      (or score not yet measured, OCR fully `:completed`)

  Accepts either a course struct or a course id.
  """
  @spec textbook_status(Course.t() | Ecto.UUID.t()) :: %{
          status: :missing | :processing | :partial | :complete,
          material: FunSheep.Content.UploadedMaterial.t() | nil,
          completeness_score: float() | nil,
          notes: String.t() | nil,
          candidate_count: non_neg_integer()
        }
  def textbook_status(%Course{id: id}), do: textbook_status(id)

  def textbook_status(course_id) when is_binary(course_id) do
    materials = textbook_materials_with_counts(course_id)

    case materials do
      [] ->
        empty_status(:missing, 0)

      _ ->
        best = pick_most_complete(materials)
        status = classify(best)

        %{
          status: status,
          material: best.material,
          completeness_score: best.material.completeness_score,
          notes: best.material.completeness_notes,
          candidate_count: length(materials)
        }
    end
  end

  defp empty_status(status, count) do
    %{
      status: status,
      material: nil,
      completeness_score: nil,
      notes: nil,
      candidate_count: count
    }
  end

  defp textbook_materials_with_counts(course_id) do
    from(m in FunSheep.Content.UploadedMaterial,
      left_join: p in FunSheep.Content.OcrPage,
      on: p.material_id == m.id,
      where: m.course_id == ^course_id and m.material_kind == :textbook,
      group_by: m.id,
      select: %{material: m, page_count: count(p.id)}
    )
    |> Repo.all()
  end

  defp pick_most_complete(materials) do
    Enum.max_by(materials, fn %{material: m, page_count: pages} ->
      score = m.completeness_score || 0.0
      # Treat completed-but-unscored as "pretty good" so the user-uploaded
      # full book beats a :pending one when scores are missing.
      baseline =
        case m.ocr_status do
          :completed -> 0.5
          :partial -> 0.2
          _ -> 0.0
        end

      {max(score, baseline), pages}
    end)
  end

  defp classify(%{material: m}) do
    cond do
      m.ocr_status in [:pending, :processing] ->
        :processing

      m.ocr_status == :failed ->
        :missing

      is_float(m.completeness_score) and m.completeness_score >= @completeness_threshold ->
        :complete

      is_float(m.completeness_score) ->
        :partial

      m.ocr_status == :partial ->
        :partial

      m.ocr_status == :completed ->
        :complete

      true ->
        :processing
    end
  end

  @doc "Atomically increment ocr_completed_count and return the new count + total."
  def increment_ocr_completed(course_id) do
    {1, [result]} =
      from(c in Course,
        where: c.id == ^course_id,
        select: {c.ocr_completed_count, c.ocr_total_count}
      )
      |> Repo.update_all(inc: [ocr_completed_count: 1])

    {elem(result, 0), elem(result, 1)}
  end

  @doc "Returns the IDs of materials that have completed OCR for a course."
  def list_completed_material_ids(course_id) do
    alias FunSheep.Content.UploadedMaterial

    from(m in UploadedMaterial,
      where: m.course_id == ^course_id and m.ocr_status == :completed,
      select: m.id
    )
    |> Repo.all()
  end

  @doc """
  Record when OCR first started. Uses a conditional update so concurrent
  workers don't overwrite the initial timestamp.
  """
  def set_ocr_started_at(course_id) do
    from(c in Course,
      where: c.id == ^course_id and is_nil(c.ocr_started_at),
      update: [set: [ocr_started_at: ^DateTime.utc_now()]]
    )
    |> Repo.update_all([])
  end

  ## Textbooks

  @doc """
  Searches textbooks in the local database by subject and optional grade/query.
  """
  def search_textbooks(subject, grade \\ nil, query \\ nil) do
    Textbook
    |> where([t], ilike(t.subject, ^"%#{subject}%"))
    |> maybe_filter_textbook_grade(grade)
    |> maybe_filter_textbook_query(query)
    |> order_by([t], asc: t.title)
    |> limit(20)
    |> Repo.all()
  end

  defp maybe_filter_textbook_grade(q, nil), do: q
  defp maybe_filter_textbook_grade(q, ""), do: q

  defp maybe_filter_textbook_grade(q, grade) do
    where(q, [t], fragment("? = ANY(?)", ^grade, t.grades) or t.grades == ^[])
  end

  defp maybe_filter_textbook_query(q, nil), do: q
  defp maybe_filter_textbook_query(q, ""), do: q

  defp maybe_filter_textbook_query(q, query) do
    pattern = "%#{query}%"

    where(
      q,
      [t],
      ilike(t.title, ^pattern) or
        ilike(t.author, ^pattern) or
        ilike(t.publisher, ^pattern)
    )
  end

  def get_textbook!(id), do: Repo.get!(Textbook, id)

  @doc """
  Finds or creates a textbook from OpenLibrary API data.
  Returns the existing record if the openlibrary_key is already stored.
  """
  def find_or_create_textbook(attrs) do
    case Repo.get_by(Textbook,
           openlibrary_key: attrs[:openlibrary_key] || attrs["openlibrary_key"]
         ) do
      nil ->
        %Textbook{}
        |> Textbook.changeset(attrs)
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  ## Chapters

  def list_chapters do
    Repo.all(Chapter)
  end

  def list_chapters_by_course(course_id) do
    sections_query = from(s in Section, order_by: s.position)

    from(c in Chapter,
      where: c.course_id == ^course_id,
      order_by: c.position,
      preload: [sections: ^sections_query]
    )
    |> Repo.all()
  end

  @doc """
  Lists chapters matching the given list of IDs, ordered by `order`.
  """
  def list_chapters_by_ids(ids) when is_list(ids) do
    from(c in Chapter,
      where: c.id in ^ids,
      order_by: c.position
    )
    |> Repo.all()
  end

  def get_chapter!(id), do: Repo.get!(Chapter, id)

  def get_chapter(id), do: Repo.get(Chapter, id)

  def create_chapter(attrs \\ %{}) do
    %Chapter{}
    |> Chapter.changeset(attrs)
    |> Repo.insert()
  end

  def update_chapter(%Chapter{} = chapter, attrs) do
    chapter
    |> Chapter.changeset(attrs)
    |> Repo.update()
  end

  def delete_chapter(%Chapter{} = chapter) do
    Repo.delete(chapter)
  end

  def change_chapter(%Chapter{} = chapter, attrs \\ %{}) do
    Chapter.changeset(chapter, attrs)
  end

  @doc """
  Reorders chapters by updating their position/order fields.
  `chapter_ids` is an ordered list of chapter IDs.
  """
  def reorder_chapters(course_id, chapter_ids) when is_list(chapter_ids) do
    Repo.transaction(fn ->
      chapter_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {chapter_id, position} ->
        from(c in Chapter,
          where: c.id == ^chapter_id and c.course_id == ^course_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  ## Sections

  def list_sections do
    Repo.all(Section)
  end

  def list_sections_by_chapter(chapter_id) do
    from(s in Section,
      where: s.chapter_id == ^chapter_id,
      order_by: s.position
    )
    |> Repo.all()
  end

  @doc "All sections for any of the given chapter IDs."
  def list_sections_by_chapters([]), do: []

  def list_sections_by_chapters(chapter_ids) when is_list(chapter_ids) do
    from(s in Section,
      where: s.chapter_id in ^chapter_ids,
      order_by: [asc: s.chapter_id, asc: s.position]
    )
    |> Repo.all()
  end

  @doc "Batched section lookup by ID, with chapter preloaded."
  def list_sections_by_ids([]), do: []

  def list_sections_by_ids(ids) when is_list(ids) do
    from(s in Section, where: s.id in ^ids, preload: [:chapter])
    |> Repo.all()
  end

  def get_section!(id), do: Repo.get!(Section, id)

  def get_section(id), do: Repo.get(Section, id)

  def create_section(attrs \\ %{}) do
    %Section{}
    |> Section.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a usable Section for `chapter_id`. If the chapter has at least one
  section already, returns the lowest-positioned one. Otherwise creates a
  single "Overview" section and returns it.

  This unblocks the delivery pipeline for courses where TOC discovery only
  produced chapter-level structure (no `sections` array on the AI's chapter
  output). North Star invariant I-1 requires every adaptive-flow question
  to carry a `section_id`; without this fallback, those courses end up with
  every question stuck at `classification_status = :low_confidence` and
  invisible to practice / quick-test / readiness.

  Idempotent — safe to call repeatedly. Race-tolerant: a unique-on
  `(chapter_id, name)` race resolves to the existing row on retry.
  """
  @spec ensure_default_section(binary()) :: {:ok, Section.t()} | {:error, Ecto.Changeset.t()}
  def ensure_default_section(chapter_id) when is_binary(chapter_id) do
    case list_sections_by_chapter(chapter_id) do
      [first | _] ->
        {:ok, first}

      [] ->
        case create_section(%{name: "Overview", position: 1, chapter_id: chapter_id}) do
          {:ok, section} ->
            {:ok, section}

          {:error, _} = err ->
            # Loser of an insert race re-queries — by then the winner's row exists.
            case list_sections_by_chapter(chapter_id) do
              [first | _] -> {:ok, first}
              [] -> err
            end
        end
    end
  end

  def update_section(%Section{} = section, attrs) do
    section
    |> Section.changeset(attrs)
    |> Repo.update()
  end

  def delete_section(%Section{} = section) do
    Repo.delete(section)
  end

  def change_section(%Section{} = section, attrs \\ %{}) do
    Section.changeset(section, attrs)
  end

  @doc """
  Reorders sections by updating their position/order fields.
  `section_ids` is an ordered list of section IDs.
  """
  def reorder_sections(chapter_id, section_ids) when is_list(section_ids) do
    Repo.transaction(fn ->
      section_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {section_id, position} ->
        from(s in Section,
          where: s.id == ^section_id and s.chapter_id == ^chapter_id
        )
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  @doc """
  Returns the next available order value for a new chapter in a course.
  """
  def next_chapter_position(course_id) do
    from(c in Chapter,
      where: c.course_id == ^course_id,
      select: coalesce(max(c.position), 0)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

  @doc """
  Returns the next available order value for a new section in a chapter.
  """
  def next_section_position(chapter_id) do
    from(s in Section,
      where: s.chapter_id == ^chapter_id,
      select: coalesce(max(s.position), 0)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end
end
