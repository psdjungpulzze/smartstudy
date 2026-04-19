defmodule FunSheep.Questions do
  @moduledoc """
  The Questions context.

  Central question bank management. Handles question creation,
  tagging, and attempt recording.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Questions.{Question, QuestionAttempt, QuestionStats}

  ## Questions

  def list_questions do
    Repo.all(Question)
  end

  def count_questions_by_course(course_id) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> Repo.aggregate(:count)
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

  @doc "Gets a question with chapter and stats preloaded (for tutor context)."
  def get_question_with_context!(id) do
    Question
    |> Repo.get!(id)
    |> Repo.preload([:chapter, :stats])
  end

  @doc "Lists a student's attempts for a specific question, ordered chronologically."
  def list_attempts_for_question(user_role_id, question_id) do
    from(qa in QuestionAttempt,
      where: qa.user_role_id == ^user_role_id and qa.question_id == ^question_id,
      order_by: [asc: qa.inserted_at]
    )
    |> Repo.all()
  end

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
  def list_questions_for_quick_test(user_role_id, course_id \\ nil, limit \\ 20)
  def list_questions_for_quick_test(nil, _course_id, _limit), do: []

  def list_questions_for_quick_test(user_role_id, course_id, limit) do
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

  ## Question Stats (Aggregate / Crowd-Sourced Difficulty)

  @doc """
  Updates aggregate stats for a question after an attempt is recorded.
  Creates the stats row if it doesn't exist yet.

  This is the core of crowd-sourced difficulty: every student attempt
  feeds into the difficulty score that drives adaptive testing.
  """
  def update_question_stats(question_id, is_correct, time_taken_seconds \\ nil) do
    case Repo.get_by(QuestionStats, question_id: question_id) do
      nil ->
        %QuestionStats{}
        |> QuestionStats.changeset(%{
          question_id: question_id,
          total_attempts: 1,
          correct_attempts: if(is_correct, do: 1, else: 0),
          difficulty_score: QuestionStats.compute_difficulty(if(is_correct, do: 1, else: 0), 1),
          avg_time_seconds: (time_taken_seconds || 0) / 1.0
        })
        |> Repo.insert()

      stats ->
        new_total = stats.total_attempts + 1
        new_correct = stats.correct_attempts + if(is_correct, do: 1, else: 0)
        new_difficulty = QuestionStats.compute_difficulty(new_correct, new_total)

        new_avg_time =
          if time_taken_seconds do
            # Running average
            (stats.avg_time_seconds * stats.total_attempts + time_taken_seconds) / new_total
          else
            stats.avg_time_seconds
          end

        stats
        |> QuestionStats.changeset(%{
          total_attempts: new_total,
          correct_attempts: new_correct,
          difficulty_score: new_difficulty,
          avg_time_seconds: Float.round(new_avg_time, 1)
        })
        |> Repo.update()
    end
  end

  @doc """
  Creates a question attempt AND updates aggregate stats in one call.
  This ensures stats are always in sync with attempts.
  """
  def record_attempt_with_stats(attrs) do
    case create_question_attempt(attrs) do
      {:ok, attempt} ->
        update_question_stats(
          attempt.question_id,
          attempt.is_correct,
          attempt.time_taken_seconds
        )

        {:ok, attempt}

      error ->
        error
    end
  end

  @doc """
  Gets stats for a question. Returns nil if no attempts yet.
  """
  def get_question_stats(question_id) do
    Repo.get_by(QuestionStats, question_id: question_id)
  end

  @doc """
  Gets stats for multiple questions at once (batch lookup).
  Returns a map of question_id => %QuestionStats{}.
  """
  def get_bulk_question_stats(question_ids) when is_list(question_ids) do
    from(qs in QuestionStats,
      where: qs.question_id in ^question_ids
    )
    |> Repo.all()
    |> Map.new(&{&1.question_id, &1})
  end

  @doc """
  Returns the crowd-sourced difficulty for a question.
  Falls back to 0.5 (medium) if no stats exist.
  """
  def crowd_difficulty(question_id) do
    case get_question_stats(question_id) do
      nil -> 0.5
      stats -> stats.difficulty_score
    end
  end

  @doc """
  Lists questions for a course with their stats preloaded.
  """
  def list_questions_with_stats(course_id, filters \\ %{}) do
    Question
    |> where([q], q.course_id == ^course_id)
    |> maybe_filter_chapter(filters)
    |> maybe_filter_difficulty(filters)
    |> maybe_filter_question_type(filters)
    |> maybe_filter_source_material(filters)
    |> order_by([q], desc: q.inserted_at)
    |> preload([:chapter, :section, :stats])
    |> Repo.all()
  end

  defp maybe_filter_source_material(query, %{source_material_ids: ids})
       when is_list(ids) and ids != [] do
    where(query, [q], q.source_material_id in ^ids)
  end

  defp maybe_filter_source_material(query, %{"source_material_ids" => ids})
       when is_list(ids) and ids != [] do
    where(query, [q], q.source_material_id in ^ids)
  end

  defp maybe_filter_source_material(query, _), do: query

  @doc """
  Returns distinct source materials that have questions for a course.
  Used for the question set toggle UI.
  """
  def list_question_sources(course_id) do
    from(q in Question,
      where: q.course_id == ^course_id and not is_nil(q.source_material_id),
      join: m in FunSheep.Content.UploadedMaterial,
      on: m.id == q.source_material_id,
      select: %{
        material_id: m.id,
        file_name: m.file_name,
        question_count: count(q.id)
      },
      group_by: [m.id, m.file_name]
    )
    |> Repo.all()
  end
end
