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

  def get_section!(id), do: Repo.get!(Section, id)

  def create_section(attrs \\ %{}) do
    %Section{}
    |> Section.changeset(attrs)
    |> Repo.insert()
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
