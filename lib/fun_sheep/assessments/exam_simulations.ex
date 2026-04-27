defmodule FunSheep.Assessments.ExamSimulations do
  import Ecto.Query
  alias FunSheep.Repo
  alias FunSheep.Assessments.ExamSimulationSession

  def get_session!(id), do: Repo.get!(ExamSimulationSession, id)

  def get_active_session(user_role_id, course_id) do
    from(s in ExamSimulationSession,
      where:
        s.user_role_id == ^user_role_id and s.course_id == ^course_id and
          s.status == "in_progress",
      order_by: [desc: s.started_at],
      limit: 1
    )
    |> Repo.one()
  end

  def list_sessions(user_role_id, opts \\ []) do
    course_id = Keyword.get(opts, :course_id)
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)

    from(s in ExamSimulationSession,
      where: s.user_role_id == ^user_role_id,
      order_by: [desc: s.started_at],
      limit: ^limit
    )
    |> then(fn q -> if course_id, do: where(q, [s], s.course_id == ^course_id), else: q end)
    |> then(fn q -> if status, do: where(q, [s], s.status == ^to_string(status)), else: q end)
    |> Repo.all()
  end

  def create_session(attrs) do
    %ExamSimulationSession{}
    |> ExamSimulationSession.changeset(attrs)
    |> Repo.insert()
  end

  def persist_answers(session, answers) do
    session
    |> ExamSimulationSession.answer_changeset(answers)
    |> Repo.update()
  end

  def mark_submitted(session, scoring_attrs) do
    attrs = Map.merge(scoring_attrs, %{submitted_at: DateTime.utc_now(:second)})

    session
    |> ExamSimulationSession.submit_changeset(attrs)
    |> Repo.update()
  end

  def mark_timed_out(session, scoring_attrs) do
    attrs = Map.merge(scoring_attrs, %{submitted_at: DateTime.utc_now(:second)})

    session
    |> ExamSimulationSession.timeout_changeset(attrs)
    |> Repo.update()
  end

  def mark_abandoned(session) do
    session
    |> ExamSimulationSession.abandoned_changeset()
    |> Repo.update()
  end

  def count_in_scope(course_id, chapter_ids) when is_list(chapter_ids) and chapter_ids != [] do
    from(q in FunSheep.Questions.Question,
      where: q.course_id == ^course_id and q.chapter_id in ^chapter_ids,
      where: q.validation_status == "passed",
      select: count()
    )
    |> Repo.one()
  end

  def count_in_scope(course_id, _) do
    from(q in FunSheep.Questions.Question,
      where: q.course_id == ^course_id,
      where: q.validation_status == "passed",
      select: count()
    )
    |> Repo.one()
  end
end
