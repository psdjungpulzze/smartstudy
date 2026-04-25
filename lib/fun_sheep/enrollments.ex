defmodule FunSheep.Enrollments do
  @moduledoc """
  The Enrollments context.

  Manages student course enrollments — enrolling, dropping, and
  listing courses for a student user role.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Enrollments.StudentCourse

  @doc """
  Enroll a student (by user_role_id) in a course.

  Idempotent — uses `on_conflict: :nothing` so re-enrolling a
  student who is already enrolled returns `{:ok, nil}` rather
  than an error.
  """
  def enroll(user_role_id, course_id, source \\ "self_enrolled") do
    %StudentCourse{}
    |> StudentCourse.changeset(%{
      user_role_id: user_role_id,
      course_id: course_id,
      status: "active",
      enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second),
      source: source
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_role_id, :course_id])
  end

  @doc """
  Enroll a student in multiple courses at once.

  Returns `{:ok, [StudentCourse.t()]}` when all succeed, or
  `{:error, errors}` (a list of `{:error, changeset}` tuples)
  when any insertion fails.
  """
  def bulk_enroll(user_role_id, course_ids, source \\ "onboarding")
      when is_list(course_ids) do
    results =
      Enum.map(course_ids, fn course_id ->
        enroll(user_role_id, course_id, source)
      end)

    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if errors == [] do
      enrolled =
        Enum.flat_map(results, fn
          {:ok, nil} -> []
          {:ok, sc} -> [sc]
        end)

      {:ok, enrolled}
    else
      {:error, errors}
    end
  end

  @doc """
  Lists active enrollments for a student, preloading the course and school.
  """
  def list_for_student(user_role_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")

    from(sc in StudentCourse,
      where: sc.user_role_id == ^user_role_id and sc.status == ^status,
      preload: [course: :school],
      order_by: [desc: sc.enrolled_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns all course IDs a student is actively enrolled in.
  """
  def enrolled_course_ids(user_role_id) do
    from(sc in StudentCourse,
      where: sc.user_role_id == ^user_role_id and sc.status == "active",
      select: sc.course_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns true if the student is currently actively enrolled in the course.
  """
  def enrolled?(user_role_id, course_id) do
    Repo.exists?(
      from sc in StudentCourse,
        where:
          sc.user_role_id == ^user_role_id and sc.course_id == ^course_id and
            sc.status == "active"
    )
  end

  @doc """
  Drops a student from a course by setting status to "dropped".
  """
  def drop(user_role_id, course_id) do
    case Repo.get_by(StudentCourse, user_role_id: user_role_id, course_id: course_id) do
      nil -> {:error, :not_found}
      sc -> Repo.update(StudentCourse.changeset(sc, %{status: "dropped"}))
    end
  end

  @doc """
  Archives an enrollment — removes the course from the student's active list
  but keeps the record for history.
  """
  def archive(user_role_id, course_id) do
    case Repo.get_by(StudentCourse, user_role_id: user_role_id, course_id: course_id) do
      nil -> {:error, :not_found}
      sc -> Repo.update(StudentCourse.changeset(sc, %{status: "archived"}))
    end
  end

  @doc """
  Soft-deletes an enrollment by flagging it as "deleted". The record is
  retained in the database per industry best practice.
  """
  def soft_delete(user_role_id, course_id) do
    case Repo.get_by(StudentCourse, user_role_id: user_role_id, course_id: course_id) do
      nil -> {:error, :not_found}
      sc -> Repo.update(StudentCourse.changeset(sc, %{status: "deleted"}))
    end
  end
end
