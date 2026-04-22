defmodule FunSheep.Learning do
  @moduledoc """
  The Learning context.

  Manages study guides, hobbies, and student hobby preferences.
  Provides hobby context for personalized question generation.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Learning.{StudyGuide, Hobby, StudentHobby}

  ## Study Guides

  def list_study_guides do
    Repo.all(StudyGuide)
  end

  def list_study_guides_by_user(user_role_id) do
    from(sg in StudyGuide,
      where: sg.user_role_id == ^user_role_id,
      order_by: [desc: sg.generated_at]
    )
    |> Repo.all()
  end

  def list_study_guides_for_user(user_role_id) do
    from(sg in StudyGuide,
      where: sg.user_role_id == ^user_role_id,
      order_by: [desc: sg.generated_at],
      preload: [:test_schedule]
    )
    |> Repo.all()
  end

  def list_study_guides_for_course(user_role_id, course_id) do
    from(sg in StudyGuide,
      join: ts in assoc(sg, :test_schedule),
      where: sg.user_role_id == ^user_role_id and ts.course_id == ^course_id,
      order_by: [desc: sg.generated_at],
      preload: [:test_schedule]
    )
    |> Repo.all()
  end

  def get_study_guide!(id), do: Repo.get!(StudyGuide, id)

  def create_study_guide(attrs \\ %{}) do
    %StudyGuide{}
    |> StudyGuide.changeset(attrs)
    |> Repo.insert()
  end

  def update_study_guide(%StudyGuide{} = study_guide, attrs) do
    study_guide
    |> StudyGuide.changeset(attrs)
    |> Repo.update()
  end

  def delete_study_guide(%StudyGuide{} = study_guide) do
    Repo.delete(study_guide)
  end

  def change_study_guide(%StudyGuide{} = study_guide, attrs \\ %{}) do
    StudyGuide.changeset(study_guide, attrs)
  end

  @doc """
  Toggles a section's reviewed status and updates progress counters.
  """
  def toggle_section_reviewed(%StudyGuide{} = guide, chapter_id) do
    content = guide.content
    sections = Map.get(content, "sections", [])

    updated_sections =
      Enum.map(sections, fn section ->
        if section["chapter_id"] == chapter_id do
          Map.put(section, "reviewed", !section["reviewed"])
        else
          section
        end
      end)

    sections_reviewed = Enum.count(updated_sections, & &1["reviewed"])

    updated_content =
      content
      |> Map.put("sections", updated_sections)
      |> put_in(["progress", "sections_reviewed"], sections_reviewed)

    update_study_guide(guide, %{content: updated_content})
  end

  @doc """
  Toggles a study plan day's completed status and updates progress.
  """
  def toggle_plan_day_completed(%StudyGuide{} = guide, day_number) do
    content = guide.content
    plan = Map.get(content, "study_plan", [])

    updated_plan =
      Enum.map(plan, fn day ->
        if day["day"] == day_number do
          Map.put(day, "completed", !day["completed"])
        else
          day
        end
      end)

    days_completed = Enum.count(updated_plan, & &1["completed"])

    updated_content =
      content
      |> Map.put("study_plan", updated_plan)
      |> put_in(["progress", "plan_days_completed"], days_completed)

    update_study_guide(guide, %{content: updated_content})
  end

  ## Hobbies

  def list_hobbies do
    Repo.all(Hobby)
  end

  def get_hobby!(id), do: Repo.get!(Hobby, id)

  def get_hobby_by_name(name) do
    Repo.get_by(Hobby, name: name)
  end

  def create_hobby(attrs \\ %{}) do
    %Hobby{}
    |> Hobby.changeset(attrs)
    |> Repo.insert()
  end

  def update_hobby(%Hobby{} = hobby, attrs) do
    hobby
    |> Hobby.changeset(attrs)
    |> Repo.update()
  end

  def delete_hobby(%Hobby{} = hobby) do
    Repo.delete(hobby)
  end

  def change_hobby(%Hobby{} = hobby, attrs \\ %{}) do
    Hobby.changeset(hobby, attrs)
  end

  ## Student Hobbies

  def list_student_hobbies do
    Repo.all(StudentHobby)
  end

  def list_hobbies_for_user(user_role_id) do
    from(sh in StudentHobby,
      where: sh.user_role_id == ^user_role_id,
      preload: [:hobby]
    )
    |> Repo.all()
  end

  @doc """
  Flat list of hobby names for prompt injection (tutor, question gen).
  Returns `[]` when the user has no hobbies set — caller must treat the
  empty case explicitly instead of fabricating analogies.
  """
  def hobby_names_for_user(user_role_id) do
    list_hobbies_for_user(user_role_id)
    |> Enum.map(fn sh -> sh.hobby && sh.hobby.name end)
    |> Enum.reject(&is_nil/1)
  end

  def get_student_hobby!(id), do: Repo.get!(StudentHobby, id)

  def create_student_hobby(attrs \\ %{}) do
    %StudentHobby{}
    |> StudentHobby.changeset(attrs)
    |> Repo.insert()
  end

  def update_student_hobby(%StudentHobby{} = student_hobby, attrs) do
    student_hobby
    |> StudentHobby.changeset(attrs)
    |> Repo.update()
  end

  def delete_student_hobby(%StudentHobby{} = student_hobby) do
    Repo.delete(student_hobby)
  end

  def change_student_hobby(%StudentHobby{} = student_hobby, attrs \\ %{}) do
    StudentHobby.changeset(student_hobby, attrs)
  end
end
