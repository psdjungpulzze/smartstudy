defmodule FunSheepWeb.API.V1.CoursesController do
  @moduledoc "Course listing and detail endpoints for the mobile app."

  use FunSheepWeb, :controller

  alias FunSheep.Courses

  @doc "GET /api/v1/courses — enrolled courses for the current user."
  def index(conn, _params) do
    user_role_id = conn.assigns.current_user_role.id
    courses = Courses.list_courses_with_stats(user_role_id)
    json(conn, %{data: Enum.map(courses, &course_payload/1)})
  end

  @doc "GET /api/v1/courses/:id — course detail with chapters."
  def show(conn, %{"id" => id}) do
    course = Courses.get_course_with_chapters!(id)
    json(conn, %{data: course_detail_payload(course)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "not_found"})
  end

  defp course_payload(course) do
    %{
      id: course.id,
      name: course.name,
      subject: course.subject,
      grades: course.grades,
      description: course.description,
      processing_status: course.processing_status,
      is_premium: course.is_premium_catalog,
      access_level: course.access_level
    }
  end

  defp course_detail_payload(course) do
    base = course_payload(course)

    chapters =
      case Map.get(course, :chapters, []) do
        nil -> []
        list -> Enum.map(list, &chapter_payload/1)
      end

    Map.put(base, :chapters, chapters)
  end

  defp chapter_payload(chapter) do
    %{
      id: chapter.id,
      name: chapter.name,
      order: Map.get(chapter, :order, 0)
    }
  end
end
