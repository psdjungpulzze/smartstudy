defmodule FunSheep.FixedTests do
  @moduledoc """
  Context for custom fixed-question tests.

  Separate from the adaptive assessment engine. Custom tests:
  - Serve exactly the creator-supplied questions (no bank selection)
  - Grade with exact match (case-insensitive) on answer_text
  - Do NOT update readiness scores
  - Allow multiple retakes (controlled by max_attempts)
  """

  import Ecto.Query
  alias FunSheep.Repo

  alias FunSheep.FixedTests.{
    FixedTestBank,
    FixedTestQuestion,
    FixedTestAssignment,
    FixedTestSession
  }

  # ── Bank CRUD ──────────────────────────────────────────────────────────────

  def get_bank!(id), do: Repo.get!(FixedTestBank, id)

  def get_bank_with_questions!(id) do
    FixedTestBank
    |> Repo.get!(id)
    |> Repo.preload(questions: from(q in FixedTestQuestion, order_by: q.position))
  end

  def list_banks_by_creator(user_role_id) do
    from(b in FixedTestBank,
      where: b.created_by_id == ^user_role_id and is_nil(b.archived_at),
      order_by: [desc: b.inserted_at],
      preload: [:course]
    )
    |> Repo.all()
  end

  def list_banks_by_course(course_id) do
    from(b in FixedTestBank,
      where: b.course_id == ^course_id and is_nil(b.archived_at),
      order_by: [desc: b.inserted_at]
    )
    |> Repo.all()
  end

  def create_bank(attrs) do
    %FixedTestBank{}
    |> FixedTestBank.changeset(attrs)
    |> Repo.insert()
  end

  def update_bank(%FixedTestBank{} = bank, attrs) do
    bank
    |> FixedTestBank.changeset(attrs)
    |> Repo.update()
  end

  def archive_bank(%FixedTestBank{} = bank) do
    bank
    |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  def question_count(%FixedTestBank{id: bank_id}) do
    from(q in FixedTestQuestion, where: q.bank_id == ^bank_id, select: count())
    |> Repo.one()
  end

  # ── Questions ─────────────────────────────────────────────────────────────

  def get_question!(id), do: Repo.get!(FixedTestQuestion, id)

  def add_question(%FixedTestBank{id: bank_id}, attrs) do
    next_pos = next_question_position(bank_id)

    %FixedTestQuestion{}
    |> FixedTestQuestion.changeset(
      Map.merge(attrs, %{"bank_id" => bank_id, "position" => next_pos})
    )
    |> Repo.insert()
  end

  def update_question(%FixedTestQuestion{} = question, attrs) do
    question
    |> FixedTestQuestion.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%FixedTestQuestion{} = question) do
    Repo.delete(question)
  end

  def reorder_questions(bank_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {id, pos} ->
        from(q in FixedTestQuestion, where: q.id == ^id and q.bank_id == ^bank_id)
        |> Repo.update_all(set: [position: pos])
      end)
    end)
  end

  def bulk_import_questions(%FixedTestBank{id: bank_id} = _bank, parsed_questions)
      when is_list(parsed_questions) do
    start_pos = next_question_position(bank_id)

    changesets =
      parsed_questions
      |> Enum.with_index(start_pos)
      |> Enum.map(fn {q, pos} ->
        %FixedTestQuestion{}
        |> FixedTestQuestion.changeset(Map.merge(q, %{bank_id: bank_id, position: pos}))
      end)

    invalid = Enum.find(changesets, &(!&1.valid?))

    if invalid do
      {:error, invalid}
    else
      Repo.transaction(fn ->
        Enum.map(changesets, &Repo.insert!/1)
      end)
    end
  end

  # ── Assignments ───────────────────────────────────────────────────────────

  def get_assignment!(id), do: Repo.get!(FixedTestAssignment, id)

  def list_assignments_for_student(user_role_id) do
    from(a in FixedTestAssignment,
      where: a.assigned_to_id == ^user_role_id,
      order_by: [asc: a.due_at, desc: a.inserted_at],
      preload: [bank: :course]
    )
    |> Repo.all()
  end

  def list_assignments_by_creator(user_role_id) do
    from(a in FixedTestAssignment,
      where: a.assigned_by_id == ^user_role_id,
      order_by: [desc: a.inserted_at],
      preload: [:bank, :assigned_to]
    )
    |> Repo.all()
  end

  def assign_bank(%FixedTestBank{id: bank_id}, assigned_by_id, student_ids, opts \\ [])
      when is_list(student_ids) do
    due_at = Keyword.get(opts, :due_at)
    note = Keyword.get(opts, :note)
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      Enum.map(student_ids, fn student_id ->
        case Repo.get_by(FixedTestAssignment, bank_id: bank_id, assigned_to_id: student_id) do
          nil ->
            %FixedTestAssignment{}
            |> FixedTestAssignment.changeset(%{
              bank_id: bank_id,
              assigned_by_id: assigned_by_id,
              assigned_to_id: student_id,
              due_at: due_at,
              note: note
            })
            |> Repo.insert!()

          existing ->
            existing
            |> FixedTestAssignment.changeset(%{due_at: due_at, note: note, updated_at: now})
            |> Repo.update!()
        end
      end)
    end)
  end

  # ── Sessions ──────────────────────────────────────────────────────────────

  def get_session!(id),
    do: Repo.get!(FixedTestSession, id) |> Repo.preload([:bank, :assignment])

  def list_sessions_for_bank(bank_id) do
    from(s in FixedTestSession,
      where: s.bank_id == ^bank_id,
      order_by: [desc: s.inserted_at],
      preload: [:user_role]
    )
    |> Repo.all()
  end

  def list_sessions_for_student(user_role_id) do
    from(s in FixedTestSession,
      where: s.user_role_id == ^user_role_id,
      order_by: [desc: s.inserted_at],
      preload: [bank: :course]
    )
    |> Repo.all()
  end

  def latest_session_for_student(bank_id, user_role_id) do
    from(s in FixedTestSession,
      where: s.bank_id == ^bank_id and s.user_role_id == ^user_role_id,
      order_by: [desc: s.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def completed_attempts_count(bank_id, user_role_id) do
    from(s in FixedTestSession,
      where:
        s.bank_id == ^bank_id and s.user_role_id == ^user_role_id and s.status == "completed",
      select: count()
    )
    |> Repo.one()
  end

  def start_session(bank_id, user_role_id, assignment_id \\ nil) do
    bank = get_bank_with_questions!(bank_id)

    questions_order =
      if bank.shuffle_questions do
        bank.questions |> Enum.shuffle() |> Enum.map(& &1.id)
      else
        Enum.map(bank.questions, & &1.id)
      end

    %FixedTestSession{}
    |> FixedTestSession.create_changeset(%{
      bank_id: bank_id,
      user_role_id: user_role_id,
      assignment_id: assignment_id,
      started_at: DateTime.utc_now(:second),
      questions_order: questions_order
    })
    |> Repo.insert()
  end

  def submit_answer(%FixedTestSession{} = session, question_id, answer_given, time_taken \\ nil) do
    question = get_question!(question_id)
    is_correct = grade_answer(question, answer_given)

    existing_answers = session.answers || []
    existing_index = Enum.find_index(existing_answers, &(&1["question_id"] == question_id))

    entry = %{
      "question_id" => question_id,
      "answer_given" => answer_given,
      "is_correct" => is_correct,
      "time_taken_seconds" => time_taken
    }

    new_answers =
      if existing_index do
        List.replace_at(existing_answers, existing_index, entry)
      else
        existing_answers ++ [entry]
      end

    session
    |> FixedTestSession.answer_changeset(%{answers: new_answers})
    |> Repo.update()
  end

  def complete_session(%FixedTestSession{} = session) do
    answers = session.answers || []
    score_correct = Enum.count(answers, & &1["is_correct"])
    score_total = length(answers)

    now = DateTime.utc_now(:second)

    time_taken =
      if session.started_at do
        DateTime.diff(now, session.started_at, :second)
      end

    session
    |> FixedTestSession.complete_changeset(%{
      completed_at: now,
      time_taken_seconds: time_taken,
      score_correct: score_correct,
      score_total: score_total,
      answers: answers
    })
    |> Repo.update()
  end

  def abandon_session(%FixedTestSession{} = session) do
    session
    |> FixedTestSession.abandon_changeset()
    |> Repo.update()
  end

  # ── Grading ───────────────────────────────────────────────────────────────

  def grade_answer(%FixedTestQuestion{question_type: "short_answer"} = q, given) do
    normalize(given) == normalize(q.answer_text)
  end

  def grade_answer(%FixedTestQuestion{} = q, given) do
    normalize(given) == normalize(q.answer_text)
  end

  defp normalize(nil), do: ""
  defp normalize(s), do: s |> String.trim() |> String.downcase()

  # ── Access control ────────────────────────────────────────────────────────

  def can_take?(%FixedTestBank{} = bank, user_role_id) do
    bank.created_by_id == user_role_id or
      has_assignment?(bank.id, user_role_id) or
      bank.visibility in ~w(class school shared_link)
  end

  def can_manage?(%FixedTestBank{created_by_id: creator_id}, user_role_id) do
    creator_id == user_role_id
  end

  def within_attempt_limit?(%FixedTestBank{max_attempts: nil}, _user_role_id), do: true

  def within_attempt_limit?(%FixedTestBank{max_attempts: max, id: bank_id}, user_role_id) do
    completed_attempts_count(bank_id, user_role_id) < max
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp next_question_position(bank_id) do
    from(q in FixedTestQuestion,
      where: q.bank_id == ^bank_id,
      select: coalesce(max(q.position), 0)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp has_assignment?(bank_id, user_role_id) do
    from(a in FixedTestAssignment,
      where: a.bank_id == ^bank_id and a.assigned_to_id == ^user_role_id,
      select: count()
    )
    |> Repo.one()
    |> Kernel.>(0)
  end
end
