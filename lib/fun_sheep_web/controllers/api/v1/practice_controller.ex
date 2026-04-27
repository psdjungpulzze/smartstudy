defmodule FunSheepWeb.API.V1.PracticeController do
  @moduledoc """
  Practice card endpoints for the mobile app.

  The mobile client fetches a batch of questions, presents them locally
  (including offline), then posts answers in bulk when connectivity returns.
  """

  use FunSheepWeb, :controller

  alias FunSheep.Assessments.PracticeEngine
  alias FunSheep.Questions

  @doc """
  GET /api/v1/courses/:course_id/practice/questions

  Returns up to `limit` (default 20, max 50) practice questions weighted
  by the student's weak topics. Questions include the correct answer so the
  mobile app can grade locally and support offline use.

  Optional query params:
    - limit        — number of questions (1–50)
    - chapter_id   — filter to one chapter
  """
  def questions(conn, %{"course_id" => course_id} = params) do
    user_role_id = conn.assigns.current_user_role.id
    limit = min(to_int(params["limit"], 20), 50)
    chapter_id = params["chapter_id"]

    opts = %{
      limit: limit,
      chapter_id: chapter_id,
      chapter_ids: if(chapter_id, do: [chapter_id], else: [])
    }

    state = PracticeEngine.start_practice(user_role_id, course_id, opts)
    questions = state.questions || []

    json(conn, %{data: Enum.map(questions, &question_payload/1)})
  end

  @doc """
  POST /api/v1/practice/answers

  Records a batch of answers from a completed practice session.

  Body (JSON):
    {
      "course_id": "uuid",
      "answers": [
        {
          "question_id": "uuid",
          "answer": "A",
          "is_correct": true,
          "time_ms": 1200
        }
      ]
    }
  """
  def record_answers(conn, %{"course_id" => course_id, "answers" => answers})
      when is_list(answers) do
    user_role_id = conn.assigns.current_user_role.id

    results =
      Enum.map(answers, fn ans ->
        question_id = ans["question_id"]
        answer = ans["answer"]
        is_correct = ans["is_correct"] == true
        time_ms = to_int(ans["time_ms"], 0)

        Questions.record_attempt_with_stats(%{
          user_role_id: user_role_id,
          question_id: question_id,
          answer_given: answer,
          is_correct: is_correct,
          time_taken_seconds: div(time_ms, 1000)
        })

        %{question_id: question_id, recorded: true}
      end)

    json(conn, %{data: results})
  end

  def record_answers(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "course_id and answers array are required"})
  end

  defp question_payload(q) do
    %{
      id: q.id,
      content: q.content,
      type: q.question_type,
      options: q.options,
      correct_answer: q.answer,
      explanation: q.explanation,
      chapter: chapter_name(q),
      difficulty: q.difficulty
    }
  end

  defp chapter_name(%{chapter: %{name: name}}), do: name
  defp chapter_name(%{section: %{name: name}}), do: name
  defp chapter_name(_), do: nil

  defp to_int(nil, default), do: default
  defp to_int(val, _default) when is_integer(val), do: val

  defp to_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp to_int(_, default), do: default
end
