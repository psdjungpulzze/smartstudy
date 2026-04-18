defmodule StudySmart.Learning do
  @moduledoc """
  The Learning context.

  Manages study guides, hobbies, and student hobby preferences.
  Provides hobby context for personalized question generation.
  """

  import Ecto.Query, warn: false
  alias StudySmart.Repo
  alias StudySmart.Learning.{StudyGuide, Hobby, StudentHobby}

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
