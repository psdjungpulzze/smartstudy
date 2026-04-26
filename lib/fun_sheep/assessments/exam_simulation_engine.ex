defmodule FunSheep.Assessments.ExamSimulationEngine do
  @moduledoc """
  Builds and grades exam simulation sessions.

  Intentionally NOT adaptive: question selection is fixed at session start
  and no per-answer feedback is shown until the exam is submitted (ES-1).
  """

  alias FunSheep.Assessments.{ExamSimulations, StateCache}
  alias FunSheep.Questions
  alias FunSheep.Questions.{Question, QuestionAttempt}
  alias FunSheep.Repo

  require Logger

  @default_time_limit_seconds 45 * 60
  @default_question_count 40

  # ── Session Lifecycle ──────────────────────────────────────────────────────

  @doc """
  Builds an exam session for the given user/course.

  Loads the format template (if provided), selects questions per section spec,
  persists the session record, and stores state in the ETS cache.

  Returns `{:ok, engine_state}` or `{:error, reason}`.
  """
  def build_session(user_role_id, course_id, opts \\ []) do
    schedule_id = Keyword.get(opts, :schedule_id)
    format_template_id = Keyword.get(opts, :format_template_id)
    chapter_ids = Keyword.get(opts, :chapter_ids, [])

    sections = resolve_sections(format_template_id, course_id, chapter_ids)
    {questions, section_boundaries} = select_questions(sections, course_id, chapter_ids)

    if questions == [] do
      {:error, :insufficient_questions}
    else
      time_limit = resolve_time_limit(sections)
      now = DateTime.utc_now(:second)

      attrs = %{
        user_role_id: user_role_id,
        course_id: course_id,
        schedule_id: schedule_id,
        format_template_id: format_template_id,
        time_limit_seconds: time_limit,
        started_at: now,
        question_ids_order: Enum.map(questions, & &1.id),
        section_boundaries: section_boundaries
      }

      with {:ok, session} <- ExamSimulations.create_session(attrs) do
        state = build_state(session, questions)
        cache_put(user_role_id, session.id, state)
        schedule_timeout_job(session)
        {:ok, state}
      end
    end
  end

  @doc """
  Records a student's answer for a question. Does NOT grade — grading happens at submit.
  """
  def record_answer(state, question_id, answer_text, time_spent_seconds) do
    answer_entry = %{
      "answer" => answer_text,
      "flagged" => get_in(state.answers, [question_id, "flagged"]) || false,
      "time_spent_seconds" => time_spent_seconds
    }

    new_answers = Map.put(state.answers, question_id, answer_entry)
    new_state = %{state | answers: new_answers}

    session = ExamSimulations.get_session!(state.session_id)
    ExamSimulations.persist_answers(session, new_answers)
    cache_put(state.user_role_id, state.session_id, new_state)

    new_state
  end

  @doc """
  Toggles the flagged status of a question for review.
  """
  def flag_question(state, question_id, flagged) do
    existing = Map.get(state.answers, question_id, %{})
    updated = Map.put(existing, "flagged", flagged)
    new_answers = Map.put(state.answers, question_id, updated)
    new_state = %{state | answers: new_answers}

    session = ExamSimulations.get_session!(state.session_id)
    ExamSimulations.persist_answers(session, new_answers)
    cache_put(state.user_role_id, state.session_id, new_state)

    new_state
  end

  @doc """
  Submits the exam. Grades all answers and persists the final session record.
  """
  def submit(state) do
    finalize(state, :submitted)
  end

  @doc """
  Times out the exam (called by ExamTimeoutWorker or when timer reaches 0).
  Accepts either an engine state map or a session_id string.
  """
  def timeout(%{session_id: _} = state), do: finalize(state, :timed_out)

  def timeout(session_id) when is_binary(session_id) do
    session = ExamSimulations.get_session!(session_id)

    if session.status == "in_progress" do
      questions = load_questions_by_ids(session.question_ids_order)
      state = build_state(session, questions)
      finalize(state, :timed_out)
    else
      {:ok, session}
    end
  rescue
    e ->
      Logger.warning("[ExamSimulationEngine] timeout failed for #{session_id}: #{inspect(e)}")
      :ok
  end

  # ── Results helpers ────────────────────────────────────────────────────────

  @doc "Returns remaining seconds. Negative means expired."
  def remaining_seconds(state) do
    elapsed = DateTime.diff(DateTime.utc_now(), state.started_at, :second)
    state.time_limit_seconds - elapsed
  end

  @doc "Returns a question map by its position index in question_ids_order."
  def question_at(state, index) do
    id = Enum.at(state.question_ids_order, index)
    Enum.find(state.questions, &(&1.id == id))
  end

  @doc "Returns the section index and section spec for a given question_id."
  def section_for_question(state, question_id) do
    flat_index = Enum.find_index(state.question_ids_order, &(&1 == question_id))

    result =
      Enum.find_index(state.section_boundaries, fn sec ->
        flat_index >= sec["start_index"] &&
          flat_index < sec["start_index"] + sec["question_count"]
      end)

    case result do
      nil -> {0, Enum.at(state.section_boundaries, 0)}
      idx -> {idx, Enum.at(state.section_boundaries, idx)}
    end
  end

  @doc "Returns the list of question IDs in the given section."
  def question_ids_for_section(state, section_index) do
    sec = Enum.at(state.section_boundaries, section_index)

    if sec do
      start = sec["start_index"]
      count = sec["question_count"]
      Enum.slice(state.question_ids_order, start, count)
    else
      []
    end
  end

  @doc "Counts answered questions across all sections."
  def answered_count(state) do
    Enum.count(state.answers, fn {_id, entry} ->
      Map.get(entry, "answer") not in [nil, ""]
    end)
  end

  @doc "Counts unanswered questions."
  def unanswered_count(state) do
    length(state.question_ids_order) - answered_count(state)
  end

  # ── Cache helpers ─────────────────────────────────────────────────────────

  def cache_put(user_role_id, session_id, state) do
    StateCache.put_exam(user_role_id, session_id, state)
  end

  def cache_get(user_role_id, session_id) do
    StateCache.get_exam(user_role_id, session_id)
  end

  def cache_delete(user_role_id, session_id) do
    StateCache.delete_exam(user_role_id, session_id)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp finalize(state, terminal_status) do
    {scored_answers, score_correct, score_total} = grade_all(state)
    score_pct = if score_total > 0, do: Float.round(score_correct / score_total, 4), else: 0.0
    section_scores = compute_section_scores(state, scored_answers)

    scoring_attrs = %{
      score_correct: score_correct,
      score_total: score_total,
      score_pct: score_pct,
      section_scores: section_scores
    }

    session = ExamSimulations.get_session!(state.session_id)

    result =
      case terminal_status do
        :submitted -> ExamSimulations.mark_submitted(session, scoring_attrs)
        :timed_out -> ExamSimulations.mark_timed_out(session, scoring_attrs)
      end

    case result do
      {:ok, completed_session} ->
        write_question_attempts(state, scored_answers)
        log_study_session(state, score_correct, score_total)
        cache_delete(state.user_role_id, state.session_id)
        {:ok, completed_session}

      {:error, _} = err ->
        err
    end
  end

  defp grade_all(state) do
    {scored, correct_count} =
      Enum.reduce(state.question_ids_order, {%{}, 0}, fn qid, {acc, correct} ->
        question = Enum.find(state.questions, &(&1.id == qid))
        answer_entry = Map.get(state.answers, qid, %{})
        answer_text = Map.get(answer_entry, "answer")

        is_correct =
          if question && answer_text do
            grade_answer(question, answer_text)
          else
            false
          end

        scored_entry = Map.merge(answer_entry, %{"is_correct" => is_correct})
        {Map.put(acc, qid, scored_entry), if(is_correct, do: correct + 1, else: correct)}
      end)

    total = length(state.question_ids_order)
    {scored, correct_count, total}
  end

  defp grade_answer(%Question{} = question, answer_text) do
    correct = question.answer || ""
    normalize(answer_text) == normalize(correct)
  end

  defp normalize(nil), do: ""
  defp normalize(s), do: s |> String.trim() |> String.downcase()

  defp compute_section_scores(state, scored_answers) do
    state.section_boundaries
    |> Enum.map(fn sec ->
      start = sec["start_index"]
      count = sec["question_count"]
      ids = Enum.slice(state.question_ids_order, start, count)

      correct = Enum.count(ids, fn id -> get_in(scored_answers, [id, "is_correct"]) end)

      time_seconds =
        Enum.sum(
          Enum.map(ids, fn id ->
            get_in(state.answers, [id, "time_spent_seconds"]) || 0
          end)
        )

      {sec["name"], %{"correct" => correct, "total" => count, "time_seconds" => time_seconds}}
    end)
    |> Map.new()
  end

  defp write_question_attempts(state, scored_answers) do
    now = DateTime.utc_now(:second)

    Enum.each(state.question_ids_order, fn qid ->
      question = Enum.find(state.questions, &(&1.id == qid))
      entry = Map.get(scored_answers, qid, %{})
      is_correct = Map.get(entry, "is_correct", false)
      time_taken = Map.get(entry, "time_spent_seconds")
      answer_given = Map.get(entry, "answer")

      if question do
        attrs = %{
          user_role_id: state.user_role_id,
          question_id: qid,
          answer_given: answer_given,
          is_correct: is_correct,
          time_taken_seconds: time_taken,
          difficulty_at_attempt: question.difficulty && Atom.to_string(question.difficulty),
          inserted_at: now,
          updated_at: now
        }

        %QuestionAttempt{}
        |> QuestionAttempt.changeset(attrs)
        |> Repo.insert()
      end
    end)
  end

  defp log_study_session(state, score_correct, score_total) do
    elapsed = DateTime.diff(DateTime.utc_now(), state.started_at, :second)

    case FunSheep.Engagement.StudySessions.start_session(
           state.user_role_id,
           "exam_simulation",
           course_id: state.course_id
         ) do
      {:ok, session} ->
        FunSheep.Engagement.StudySessions.complete_session(session.id, %{
          questions_attempted: score_total,
          questions_correct: score_correct,
          duration_seconds: elapsed
        })

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp build_state(session, questions) do
    %{
      session_id: session.id,
      user_role_id: session.user_role_id,
      course_id: session.course_id,
      schedule_id: session.schedule_id,
      format_template_id: session.format_template_id,
      questions: questions,
      question_ids_order: session.question_ids_order,
      section_boundaries: session.section_boundaries,
      answers: session.answers || %{},
      time_limit_seconds: session.time_limit_seconds,
      started_at: session.started_at,
      status: String.to_existing_atom(session.status)
    }
  end

  defp select_questions(sections, course_id, chapter_ids) do
    {questions, boundaries} =
      Enum.reduce(sections, {[], [], 0}, fn sec, {all_qs, bounds, start_idx} ->
        qs =
          Questions.list_for_exam(
            course_id: course_id,
            chapter_ids: chapter_ids,
            question_types: sec.question_types,
            count: sec.count
          )

        boundary = %{
          "name" => sec.name,
          "question_count" => length(qs),
          "time_budget_seconds" => sec.time_seconds,
          "start_index" => start_idx
        }

        {all_qs ++ qs, bounds ++ [boundary], start_idx + length(qs)}
      end)
      |> then(fn {qs, bounds, _} -> {qs, bounds} end)

    {questions, boundaries}
  end

  defp resolve_sections(nil, _course_id, _chapter_ids) do
    [
      %{
        name: "General",
        question_types: [],
        count: @default_question_count,
        time_seconds: @default_time_limit_seconds
      }
    ]
  end

  defp resolve_sections(format_template_id, _course_id, _chapter_ids) do
    template = Repo.get(FunSheep.Assessments.TestFormatTemplate, format_template_id)

    if template && is_map(template.structure) do
      raw_sections = Map.get(template.structure, "sections", [])

      if raw_sections != [] do
        Enum.map(raw_sections, fn sec ->
          types =
            Map.get(sec, "question_types", [])
            |> Enum.map(&string_to_question_type/1)

          %{
            name: Map.get(sec, "name", "Section"),
            question_types: Enum.reject(types, &is_nil/1),
            count: Map.get(sec, "count", 10),
            time_seconds: Map.get(sec, "time_seconds", 600)
          }
        end)
      else
        [
          %{
            name: "General",
            question_types: [],
            count: @default_question_count,
            time_seconds: @default_time_limit_seconds
          }
        ]
      end
    else
      [
        %{
          name: "General",
          question_types: [],
          count: @default_question_count,
          time_seconds: @default_time_limit_seconds
        }
      ]
    end
  end

  defp resolve_time_limit(sections) do
    total = Enum.sum(Enum.map(sections, & &1.time_seconds))
    if total > 0, do: total, else: @default_time_limit_seconds
  end

  defp string_to_question_type("multiple_choice"), do: :multiple_choice
  defp string_to_question_type("short_answer"), do: :short_answer
  defp string_to_question_type("free_response"), do: :free_response
  defp string_to_question_type("true_false"), do: :true_false
  defp string_to_question_type("essay"), do: :essay
  defp string_to_question_type(_), do: nil

  defp load_questions_by_ids(ids) when is_list(ids) do
    import Ecto.Query

    from(q in Question, where: q.id in ^ids)
    |> Repo.all()
    |> Enum.sort_by(&Enum.find_index(ids, fn id -> id == &1.id end))
  end

  defp schedule_timeout_job(session) do
    scheduled_at = DateTime.add(session.started_at, session.time_limit_seconds + 30, :second)

    %{"session_id" => session.id}
    |> FunSheep.Workers.ExamTimeoutWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  rescue
    e ->
      Logger.warning("[ExamSimulationEngine] Could not schedule timeout job: #{inspect(e)}")
  end
end
