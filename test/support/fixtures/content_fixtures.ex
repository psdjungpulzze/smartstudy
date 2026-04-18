defmodule StudySmart.ContentFixtures do
  @moduledoc """
  Test fixtures for the Content context (UploadedMaterial, OcrPage).
  """

  alias StudySmart.Repo

  @doc """
  Creates the full geo hierarchy (Country -> State -> District -> School)
  needed as a prerequisite for UserRole and Course records.
  Returns the school.
  """
  def create_school(_attrs \\ %{}) do
    {:ok, country} =
      %StudySmart.Geo.Country{}
      |> StudySmart.Geo.Country.changeset(%{
        name: "Test Country #{System.unique_integer([:positive])}",
        code: "TC#{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, state} =
      %StudySmart.Geo.State{}
      |> StudySmart.Geo.State.changeset(%{name: "Test State", country_id: country.id})
      |> Repo.insert()

    {:ok, district} =
      %StudySmart.Geo.District{}
      |> StudySmart.Geo.District.changeset(%{name: "Test District", state_id: state.id})
      |> Repo.insert()

    {:ok, school} =
      %StudySmart.Geo.School{}
      |> StudySmart.Geo.School.changeset(%{name: "Test School", district_id: district.id})
      |> Repo.insert()

    school
  end

  @doc """
  Creates a UserRole record with the given attrs merged into defaults.
  """
  def create_user_role(attrs \\ %{}) do
    school = create_school()

    defaults = %{
      interactor_user_id: "user_#{System.unique_integer([:positive])}",
      role: :student,
      email: "test#{System.unique_integer([:positive])}@example.com",
      display_name: "Test User",
      school_id: school.id
    }

    {:ok, user_role} =
      %StudySmart.Accounts.UserRole{}
      |> StudySmart.Accounts.UserRole.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    user_role
  end

  @doc """
  Creates a Course record with the given attrs merged into defaults.
  """
  def create_course(attrs \\ %{}) do
    defaults = %{
      name: "Test Course",
      subject: "Biology",
      grade: "10"
    }

    {:ok, course} =
      %StudySmart.Courses.Course{}
      |> StudySmart.Courses.Course.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    course
  end

  @doc """
  Creates an UploadedMaterial record with the given attrs merged into defaults.
  Also creates the prerequisite UserRole and Course if not provided.
  """
  def create_uploaded_material(attrs \\ %{}) do
    user_role = Map.get_lazy(attrs, :user_role, fn -> create_user_role() end)
    course = Map.get_lazy(attrs, :course, fn -> create_course() end)

    defaults = %{
      file_path: "test/#{Ecto.UUID.generate()}.pdf",
      file_name: "test_document.pdf",
      file_type: "application/pdf",
      file_size: 1024,
      ocr_status: :pending,
      user_role_id: user_role.id,
      course_id: course.id
    }

    clean_attrs = Map.drop(attrs, [:user_role, :course])

    {:ok, material} =
      %StudySmart.Content.UploadedMaterial{}
      |> StudySmart.Content.UploadedMaterial.changeset(Map.merge(defaults, clean_attrs))
      |> Repo.insert()

    material
  end
end
