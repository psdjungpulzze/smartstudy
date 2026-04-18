defmodule StudySmart.Courses do
  @moduledoc """
  The Courses context.

  Manages courses, chapters, and sections. Links courses to schools
  for per-school question filtering.
  """

  import Ecto.Query, warn: false
  alias StudySmart.Repo
  alias StudySmart.Courses.{Course, Chapter, Section}

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

  ## Chapters

  def list_chapters do
    Repo.all(Chapter)
  end

  def list_chapters_by_course(course_id) do
    from(c in Chapter,
      where: c.course_id == ^course_id,
      order_by: c.position
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
