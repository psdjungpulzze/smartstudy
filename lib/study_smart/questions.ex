defmodule StudySmart.Questions do
  @moduledoc """
  The Questions context.

  Central question bank management. Handles question creation,
  tagging, and attempt recording.
  """

  import Ecto.Query, warn: false
  alias StudySmart.Repo
  alias StudySmart.Questions.{Question, QuestionAttempt}

  ## Questions

  def list_questions do
    Repo.all(Question)
  end

  def list_questions_by_course(course_id, filters \\ %{}) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> maybe_filter_chapter(filters)
    |> maybe_filter_section(filters)
    |> maybe_filter_difficulty(filters)
    |> maybe_filter_question_type(filters)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section])
    |> Repo.all()
  end

  defp maybe_filter_chapter(query, %{"chapter_id" => chapter_id}) when chapter_id != "" do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  defp maybe_filter_chapter(query, %{chapter_id: chapter_id}) when not is_nil(chapter_id) do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  defp maybe_filter_chapter(query, _), do: query

  defp maybe_filter_section(query, %{"section_id" => section_id}) when section_id != "" do
    where(query, [q], q.section_id == ^section_id)
  end

  defp maybe_filter_section(query, _), do: query

  defp maybe_filter_difficulty(query, %{"difficulty" => difficulty}) when difficulty != "" do
    where(query, [q], q.difficulty == ^difficulty)
  end

  defp maybe_filter_difficulty(query, %{difficulty: difficulty}) when not is_nil(difficulty) do
    where(query, [q], q.difficulty == ^difficulty)
  end

  defp maybe_filter_difficulty(query, _), do: query

  defp maybe_filter_question_type(query, %{"question_type" => type}) when type != "" do
    where(query, [q], q.question_type == ^type)
  end

  defp maybe_filter_question_type(query, %{question_type: type}) when not is_nil(type) do
    where(query, [q], q.question_type == ^type)
  end

  defp maybe_filter_question_type(query, _), do: query

  def list_questions_by_chapter(chapter_id) do
    from(q in Question, where: q.chapter_id == ^chapter_id)
    |> Repo.all()
  end

  def get_question!(id), do: Repo.get!(Question, id)

  def create_question(attrs \\ %{}) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%Question{} = question) do
    Repo.delete(question)
  end

  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  ## Question Attempts

  def list_question_attempts do
    Repo.all(QuestionAttempt)
  end

  def list_attempts_by_user(user_role_id) do
    from(qa in QuestionAttempt,
      where: qa.user_role_id == ^user_role_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  def get_question_attempt!(id), do: Repo.get!(QuestionAttempt, id)

  def create_question_attempt(attrs \\ %{}) do
    %QuestionAttempt{}
    |> QuestionAttempt.changeset(attrs)
    |> Repo.insert()
  end

  def update_question_attempt(%QuestionAttempt{} = question_attempt, attrs) do
    question_attempt
    |> QuestionAttempt.changeset(attrs)
    |> Repo.update()
  end

  def delete_question_attempt(%QuestionAttempt{} = question_attempt) do
    Repo.delete(question_attempt)
  end

  def change_question_attempt(%QuestionAttempt{} = question_attempt, attrs \\ %{}) do
    QuestionAttempt.changeset(question_attempt, attrs)
  end

  @doc """
  Returns questions in a chapter where the user has at least one incorrect attempt.
  """
  def list_wrong_questions_for_chapter(user_role_id, chapter_id) do
    from(q in Question,
      join: qa in QuestionAttempt,
      on: qa.question_id == q.id,
      where:
        qa.user_role_id == ^user_role_id and
          q.chapter_id == ^chapter_id and
          qa.is_correct == false,
      distinct: q.id,
      select: q
    )
    |> Repo.all()
  end

  ## Practice & Quick Test Queries

  @doc """
  Lists questions the user has gotten wrong, prioritized by most recently wrong
  and never correctly answered. Optionally filters by chapter.
  """
  def list_weak_questions(user_role_id, course_id, chapter_id \\ nil, limit \\ 20) do
    base_query =
      from(q in Question,
        join: qa in QuestionAttempt,
        on: qa.question_id == q.id,
        left_join:
          cq in subquery(
            from(ca in QuestionAttempt,
              where: ca.user_role_id == ^user_role_id and ca.is_correct == true,
              distinct: ca.question_id,
              select: %{question_id: ca.question_id}
            )
          ),
        on: cq.question_id == q.id,
        where:
          q.course_id == ^course_id and
            qa.user_role_id == ^user_role_id and
            qa.is_correct == false,
        group_by: [q.id, cq.question_id],
        order_by: [
          # Prioritize questions never answered correctly (NULL cq means no correct attempt)
          asc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", cq.question_id),
          # Then most recently wrong
          desc: max(qa.inserted_at)
        ],
        limit: ^limit,
        preload: [:chapter]
      )

    base_query
    |> maybe_filter_chapter_for_practice(chapter_id)
    |> Repo.all()
  end

  defp maybe_filter_chapter_for_practice(query, nil), do: query

  defp maybe_filter_chapter_for_practice(query, chapter_id) do
    where(query, [q], q.chapter_id == ^chapter_id)
  end

  @doc """
  Lists questions for a quick test session. Prioritizes: wrong answers > unseen > previously correct.
  Optionally filters by course. Shuffles and limits results.
  """
  def list_questions_for_quick_test(user_role_id, course_id \\ nil, limit \\ 20) do
    base_query =
      from(q in Question,
        left_join: qa in QuestionAttempt,
        on: qa.question_id == q.id and qa.user_role_id == ^user_role_id,
        group_by: q.id,
        order_by: [
          # Wrong answers first (0), then unseen (1), then correct (2)
          asc:
            fragment(
              """
              CASE
                WHEN bool_or(COALESCE(?, false) = false AND ? IS NOT NULL) THEN 0
                WHEN NOT bool_or(? IS NOT NULL) THEN 1
                ELSE 2
              END
              """,
              qa.is_correct,
              qa.id,
              qa.id
            ),
          asc: fragment("random()")
        ],
        limit: ^limit,
        preload: [:chapter]
      )

    base_query
    |> maybe_filter_course_for_quick_test(course_id)
    |> Repo.all()
  end

  defp maybe_filter_course_for_quick_test(query, nil), do: query

  defp maybe_filter_course_for_quick_test(query, course_id) do
    where(query, [q], q.course_id == ^course_id)
  end

  ## Attempt Tracking / Aggregation

  @doc """
  Lists attempts for a user and course, preloading the question.
  """
  def list_attempts_for_user_and_course(user_role_id, course_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.course_id == ^course_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  @doc """
  Lists attempts for a user and chapter, preloading the question.
  """
  def list_attempts_for_user_and_chapter(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.chapter_id == ^chapter_id,
      order_by: [desc: qa.inserted_at],
      preload: [:question]
    )
    |> Repo.all()
  end

  @doc """
  Counts correct attempts for a user in a specific chapter.
  """
  def count_correct_attempts(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where:
        qa.user_role_id == ^user_role_id and
          q.chapter_id == ^chapter_id and
          qa.is_correct == true,
      select: count(qa.id)
    )
    |> Repo.one()
  end

  @doc """
  Counts total attempts for a user in a specific chapter.
  """
  def count_total_attempts(user_role_id, chapter_id) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.chapter_id == ^chapter_id,
      select: count(qa.id)
    )
    |> Repo.one()
  end
end
