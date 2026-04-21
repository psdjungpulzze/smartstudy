defmodule FunSheep.ContentFixtures do
  @moduledoc """
  Test fixtures for the Content context (UploadedMaterial, OcrPage).
  """

  alias FunSheep.Repo

  @doc """
  Creates the full geo hierarchy (Country -> State -> District -> School)
  needed as a prerequisite for UserRole and Course records.
  Returns the school.
  """
  def create_school(_attrs \\ %{}) do
    {:ok, country} =
      %FunSheep.Geo.Country{}
      |> FunSheep.Geo.Country.changeset(%{
        name: "Test Country #{System.unique_integer([:positive])}",
        code: "TC#{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, state} =
      %FunSheep.Geo.State{}
      |> FunSheep.Geo.State.changeset(%{name: "Test State", country_id: country.id})
      |> Repo.insert()

    {:ok, district} =
      %FunSheep.Geo.District{}
      |> FunSheep.Geo.District.changeset(%{name: "Test District", state_id: state.id})
      |> Repo.insert()

    {:ok, school} =
      %FunSheep.Geo.School{}
      |> FunSheep.Geo.School.changeset(%{name: "Test School", district_id: district.id})
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
      %FunSheep.Accounts.UserRole{}
      |> FunSheep.Accounts.UserRole.changeset(Map.merge(defaults, attrs))
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
      %FunSheep.Courses.Course{}
      |> FunSheep.Courses.Course.changeset(Map.merge(defaults, attrs))
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

    # Default to an image type so tests that invoke the OCR pipeline hit
    # the synchronous single-page path; PDF tests explicitly override
    # file_type to "application/pdf" to exercise the async dispatch path.
    defaults = %{
      file_path: "test/#{Ecto.UUID.generate()}.jpg",
      file_name: "test_image.jpg",
      file_type: "image/jpeg",
      file_size: 1024,
      ocr_status: :pending,
      user_role_id: user_role.id,
      course_id: course.id
    }

    clean_attrs = Map.drop(attrs, [:user_role, :course])

    {:ok, material} =
      %FunSheep.Content.UploadedMaterial{}
      |> FunSheep.Content.UploadedMaterial.changeset(Map.merge(defaults, clean_attrs))
      |> Repo.insert()

    material
  end
end
