defmodule FunSheep.Engagement.DailyChallenges do
  @moduledoc """
  The Daily Challenges context ("Daily Shear").

  Manages daily challenge creation, attempts, scoring, and leaderboards.
  Each course gets one challenge per day with 5 shared questions. All
  students in the same course compete on the same question set.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Engagement.{DailyChallenge, DailyChallengeAttempt}
  alias FunSheep.Questions.Question

  @target_count 5
  @leaderboard_limit 20
  @history_days 30

  ## Challenges

  @doc """
  Gets today's challenge for a course, creating one if it doesn't exist.

  When creating, randomly selects 5 questions from the course with a
  difficulty mix of 2 easy, 2 medium, and 1 hard. Falls back to whatever
  questions are available if the ideal mix cannot be satisfied.

  Returns `{:ok, challenge}` or `{:error, changeset}`.
  """
  def get_or_create_today(course_id) do
    today = Date.utc_today()

    case get_challenge(today, course_id) do
      %DailyChallenge{} = challenge ->
        {:ok, challenge}

      nil ->
        question_ids = select_question_ids(course_id)
        create_challenge(today, course_id, question_ids)
    end
  end

  @doc """
  Gets today's challenge for a course, or `nil` if none exists.
  """
  def get_today(course_id) do
    get_challenge(Date.utc_today(), course_id)
  end

  ## Attempts

  @doc """
  Returns `true` if the user has already attempted the given challenge.
  """
  def attempt_exists?(user_role_id, challenge_id) do
    DailyChallengeAttempt
    |> where([a], a.user_role_id == ^user_role_id and a.daily_challenge_id == ^challenge_id)
    |> Repo.exists?()
  end

  @doc """
  Gets the user's attempt for a challenge, or `nil` if none exists.
  """
  def get_user_attempt(user_role_id, challenge_id) do
    DailyChallengeAttempt
    |> where([a], a.user_role_id == ^user_role_id and a.daily_challenge_id == ^challenge_id)
    |> Repo.one()
  end

  @doc """
  Creates a new attempt record with empty answers.

  Returns `{:error, :already_attempted}` if the user has already attempted
  this challenge, or `{:ok, attempt}` on success.
  """
  def start_attempt(user_role_id, challenge_id) do
    if attempt_exists?(user_role_id, challenge_id) do
      {:error, :already_attempted}
    else
      %DailyChallengeAttempt{}
      |> DailyChallengeAttempt.changeset(%{
        user_role_id: user_role_id,
        daily_challenge_id: challenge_id,
        answers: %{}
      })
      |> Repo.insert()
    end
  end

  @doc """
  Records a single answer within an attempt.

  Merges the answer into the attempt's answers map keyed by `question_id`.
  Each entry stores `answer_given` and `is_correct`.

  Returns `{:ok, updated_attempt}`.
  """
  def submit_answer(attempt_id, question_id, answer_given, is_correct) do
    attempt = Repo.get!(DailyChallengeAttempt, attempt_id)

    new_entry = %{
      "answer_given" => answer_given,
      "is_correct" => is_correct,
      "answered_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    updated_answers = Map.put(attempt.answers || %{}, question_id, new_entry)

    attempt
    |> DailyChallengeAttempt.changeset(%{answers: updated_answers})
    |> Repo.update()
  end

  @doc """
  Marks an attempt as complete.

  Calculates the final score (count of correct answers) and total time
  in milliseconds from attempt creation to now. Sets `completed_at`.

  Returns `{:ok, attempt}`.
  """
  def complete_attempt(attempt_id, total_time_ms) do
    attempt = Repo.get!(DailyChallengeAttempt, attempt_id)

    score =
      (attempt.answers || %{})
      |> Map.values()
      |> Enum.count(fn entry -> entry["is_correct"] == true end)

    attempt
    |> DailyChallengeAttempt.changeset(%{
      score: score,
      total_time_ms: total_time_ms,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  ## Leaderboard & Stats

  @doc """
  Returns the ranked leaderboard for today's challenge on a course.

  Includes user display_name, score, and total_time_ms for completed
  attempts. Ranked by highest score first, then fastest time.
  Limited to the top #{@leaderboard_limit} entries.
  """
  def today_leaderboard(course_id) do
    today = Date.utc_today()

    from(a in DailyChallengeAttempt,
      join: c in DailyChallenge,
      on: a.daily_challenge_id == c.id,
      join: u in FunSheep.Accounts.UserRole,
      on: a.user_role_id == u.id,
      where: c.course_id == ^course_id and c.challenge_date == ^today,
      where: not is_nil(a.completed_at),
      order_by: [desc: a.score, asc: a.total_time_ms],
      limit: ^@leaderboard_limit,
      select: %{
        user_role_id: u.id,
        display_name: u.display_name,
        score: a.score,
        total_time_ms: a.total_time_ms,
        completed_at: a.completed_at
      }
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :rank, rank) end)
  end

  @doc """
  Returns recent challenge attempts for a user across all courses.

  Covers the last #{@history_days} days, ordered most recent first.
  """
  def user_challenge_history(user_role_id, days \\ @history_days) do
    cutoff = Date.utc_today() |> Date.add(-days)

    from(a in DailyChallengeAttempt,
      join: c in DailyChallenge,
      on: a.daily_challenge_id == c.id,
      where: a.user_role_id == ^user_role_id,
      where: c.challenge_date >= ^cutoff,
      order_by: [desc: c.challenge_date],
      preload: [daily_challenge: c]
    )
    |> Repo.all()
  end

  @doc """
  Returns aggregate stats for a challenge.

  Includes total_attempts, average_score, fastest_time (ms),
  and completion_rate (fraction of attempts that were completed).
  """
  def challenge_stats(challenge_id) do
    from(a in DailyChallengeAttempt,
      where: a.daily_challenge_id == ^challenge_id,
      select: %{
        total_attempts: count(a.id),
        average_score: avg(a.score),
        fastest_time:
          fragment(
            "MIN(CASE WHEN ? IS NOT NULL THEN ? END)",
            a.completed_at,
            a.total_time_ms
          ),
        completed_count: fragment("COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)", a.completed_at)
      }
    )
    |> Repo.one()
    |> maybe_add_completion_rate()
  end

  ## Private helpers

  defp get_challenge(date, course_id) do
    DailyChallenge
    |> where([c], c.challenge_date == ^date and c.course_id == ^course_id)
    |> Repo.one()
  end

  defp create_challenge(date, course_id, question_ids) do
    %DailyChallenge{}
    |> DailyChallenge.changeset(%{
      challenge_date: date,
      course_id: course_id,
      question_ids: question_ids,
      metadata: %{generated_at: DateTime.utc_now() |> DateTime.to_iso8601()}
    })
    |> Repo.insert()
  end

  defp select_question_ids(course_id) do
    easy = pick_random_ids(course_id, :easy, 2)
    medium = pick_random_ids(course_id, :medium, 2)
    hard = pick_random_ids(course_id, :hard, 1)

    selected = easy ++ medium ++ hard

    case length(selected) do
      n when n >= @target_count ->
        Enum.take(selected, @target_count)

      n when n > 0 ->
        # Fill remaining slots with any other questions from the course
        remaining = @target_count - n
        fill_ids = pick_random_ids_excluding(course_id, selected, remaining)
        selected ++ fill_ids

      _ ->
        # No difficulty-filtered results; grab whatever is available
        pick_random_ids_any(course_id, @target_count)
    end
  end

  defp pick_random_ids(course_id, difficulty, count) do
    from(q in Question,
      where: q.course_id == ^course_id and q.difficulty == ^difficulty,
      order_by: fragment("RANDOM()"),
      limit: ^count,
      select: q.id
    )
    |> Repo.all()
  end

  defp pick_random_ids_excluding(course_id, exclude_ids, count) do
    from(q in Question,
      where: q.course_id == ^course_id and q.id not in ^exclude_ids,
      order_by: fragment("RANDOM()"),
      limit: ^count,
      select: q.id
    )
    |> Repo.all()
  end

  defp pick_random_ids_any(course_id, count) do
    from(q in Question,
      where: q.course_id == ^course_id,
      order_by: fragment("RANDOM()"),
      limit: ^count,
      select: q.id
    )
    |> Repo.all()
  end

  defp maybe_add_completion_rate(nil), do: nil

  defp maybe_add_completion_rate(%{total_attempts: 0} = stats) do
    Map.put(stats, :completion_rate, 0.0)
  end

  defp maybe_add_completion_rate(%{total_attempts: total, completed_count: completed} = stats) do
    rate = if total > 0, do: completed / total, else: 0.0
    stats |> Map.put(:completion_rate, rate) |> Map.delete(:completed_count)
  end
end
