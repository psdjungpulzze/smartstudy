defmodule FunSheep.Engagement.SpacedRepetition do
  @moduledoc """
  SM-2 spaced repetition algorithm for review cards.

  Manages the lifecycle of review cards from creation (triggered by wrong
  answers) through graduated mastery. Cards progress through statuses:

    new → learning → review → graduated

  The SM-2 algorithm adjusts interval and ease factor based on a 0-5
  quality rating provided after each review.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Engagement.ReviewCard
  alias FunSheep.Questions.QuestionAttempt

  @min_ease_factor 1.3
  @graduation_threshold_days 30
  @learning_retry_minutes 10
  @default_batch_size 5

  ## Card Creation

  @doc """
  Creates review cards from recent incorrect question attempts.

  Queries the most recent incorrect attempts for the given user and course,
  then inserts review cards with `next_review_at` set to now (immediately due).
  Uses `ON CONFLICT DO NOTHING` to skip questions that already have a card.

  Returns `{:ok, count}` with the number of cards inserted.
  """
  def create_cards_from_attempts(user_role_id, course_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    wrong_question_ids =
      QuestionAttempt
      |> where([a], a.user_role_id == ^user_role_id and a.is_correct == false)
      |> join(:inner, [a], q in assoc(a, :question))
      |> where([_a, q], q.course_id == ^course_id)
      |> select([a, _q], a.question_id)
      |> distinct(true)
      |> Repo.all()

    entries =
      Enum.map(wrong_question_ids, fn question_id ->
        %{
          id: Ecto.UUID.generate(),
          user_role_id: user_role_id,
          question_id: question_id,
          course_id: course_id,
          ease_factor: 2.5,
          interval_days: 0.0,
          repetitions: 0,
          status: "new",
          next_review_at: now,
          last_reviewed_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    case entries do
      [] ->
        {:ok, 0}

      entries ->
        {count, _} =
          Repo.insert_all(ReviewCard, entries,
            on_conflict: :nothing,
            conflict_target: [:user_role_id, :question_id]
          )

        {:ok, count}
    end
  end

  @doc """
  Finds all wrong answers for a user in a course that don't already have
  review cards, and creates them.

  Intended to be called after any practice or assessment session completes.
  Returns `{:ok, count}` with the number of new cards created.
  """
  def auto_create_from_wrong_answers(user_role_id, course_id) do
    create_cards_from_attempts(user_role_id, course_id)
  end

  ## Querying Due Cards

  @doc """
  Returns cards due for review (`next_review_at <= now`).

  Takes a `user_role_id` and an optional `course_id` filter.
  Preloads the associated question. Ordered by `next_review_at` ascending
  so the most overdue cards come first.
  """
  def due_cards(user_role_id, course_id \\ nil) do
    now = DateTime.utc_now()

    ReviewCard
    |> where([c], c.user_role_id == ^user_role_id)
    |> where([c], c.next_review_at <= ^now)
    |> maybe_filter_course(course_id)
    |> order_by([c], asc: c.next_review_at)
    |> preload(:question)
    |> Repo.all()
  end

  @doc """
  Returns the count of cards currently due for review.

  Takes a `user_role_id` and an optional `course_id` filter.
  """
  def due_card_count(user_role_id, course_id \\ nil) do
    now = DateTime.utc_now()

    ReviewCard
    |> where([c], c.user_role_id == ^user_role_id)
    |> where([c], c.next_review_at <= ^now)
    |> maybe_filter_course(course_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the next batch of due cards for a review session.

  Defaults to #{@default_batch_size} cards. Preloads question with chapter.
  """
  def next_review_batch(user_role_id, course_id \\ nil, limit \\ @default_batch_size) do
    now = DateTime.utc_now()

    ReviewCard
    |> where([c], c.user_role_id == ^user_role_id)
    |> where([c], c.next_review_at <= ^now)
    |> maybe_filter_course(course_id)
    |> order_by([c], asc: c.next_review_at)
    |> limit(^limit)
    |> preload(question: :chapter)
    |> Repo.all()
  end

  ## Core SM-2 Algorithm

  @doc """
  Applies the SM-2 algorithm to a review card.

  Takes a `card_id` and a `quality` rating (integer 0-5):

    - **0** — Complete blackout
    - **1** — Incorrect, but recognized the answer
    - **2** — Incorrect, but answer felt easy to recall
    - **3** — Correct with serious difficulty
    - **4** — Correct with minor hesitation
    - **5** — Perfect recall

  ## Behavior

    - If `quality < 3`: resets repetitions to 0, interval to 0, status to
      `"learning"`, and schedules next review in #{@learning_retry_minutes} minutes.
    - If `quality >= 3`: increments repetitions and calculates new interval:
      - Rep 1 → 1 day
      - Rep 2 → 6 days
      - Rep 3+ → `old_interval * ease_factor`
    - Ease factor is adjusted: `EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))`
      with a floor of #{@min_ease_factor}.
    - Cards with interval > #{@graduation_threshold_days} days are marked `"graduated"`.

  Returns `{:ok, updated_card}` or `{:error, changeset}`.
  """
  def review_card(card_id, quality) when quality in 0..5 do
    card = Repo.get!(ReviewCard, card_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      if quality < 3 do
        %{
          repetitions: 0,
          interval_days: 0.0,
          status: "learning",
          next_review_at: DateTime.add(now, @learning_retry_minutes * 60, :second),
          last_reviewed_at: now
        }
      else
        new_repetitions = card.repetitions + 1
        new_ef = compute_ease_factor(card.ease_factor, quality)

        new_interval =
          case new_repetitions do
            1 -> 1.0
            2 -> 6.0
            _ -> card.interval_days * new_ef
          end

        new_status =
          if new_interval > @graduation_threshold_days, do: "graduated", else: "review"

        interval_seconds = round(new_interval * 24 * 60 * 60)

        %{
          repetitions: new_repetitions,
          interval_days: new_interval,
          ease_factor: new_ef,
          status: new_status,
          next_review_at: DateTime.add(now, interval_seconds, :second),
          last_reviewed_at: now
        }
      end

    card
    |> ReviewCard.changeset(attrs)
    |> Repo.update()
  end

  ## Statistics

  @doc """
  Returns the count of cards grouped by status for a given user.

  Example return value:

      %{"new" => 5, "learning" => 3, "review" => 12, "graduated" => 8}

  Statuses with zero cards are included with a count of 0.
  """
  def cards_by_status(user_role_id, course_id \\ nil) do
    defaults = %{"new" => 0, "learning" => 0, "review" => 0, "graduated" => 0}

    counts =
      ReviewCard
      |> where([c], c.user_role_id == ^user_role_id)
      |> maybe_filter_course(course_id)
      |> group_by([c], c.status)
      |> select([c], {c.status, count(c.id)})
      |> Repo.all()
      |> Map.new()

    Map.merge(defaults, counts)
  end

  @doc """
  Returns aggregate review stats for a user.

  Returns a map with:

    - `total_cards` — total number of review cards
    - `due_now` — cards currently due for review
    - `mastered` — cards with status `"graduated"`
    - `learning` — cards with status `"new"` or `"learning"`
    - `next_due_at` — the earliest `next_review_at` across all cards, or `nil`
  """
  def review_stats(user_role_id) do
    now = DateTime.utc_now()

    base_query = where(ReviewCard, [c], c.user_role_id == ^user_role_id)

    total = Repo.aggregate(base_query, :count, :id)

    due_now =
      base_query
      |> where([c], c.next_review_at <= ^now)
      |> Repo.aggregate(:count, :id)

    mastered =
      base_query
      |> where([c], c.status == "graduated")
      |> Repo.aggregate(:count, :id)

    learning =
      base_query
      |> where([c], c.status in ["new", "learning"])
      |> Repo.aggregate(:count, :id)

    next_due_at =
      base_query
      |> where([c], c.next_review_at > ^now)
      |> select([c], min(c.next_review_at))
      |> Repo.one()

    %{
      total_cards: total,
      due_now: due_now,
      mastered: mastered,
      learning: learning,
      next_due_at: next_due_at
    }
  end

  ## Private Helpers

  defp compute_ease_factor(old_ef, quality) do
    q = quality
    new_ef = old_ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    max(@min_ease_factor, new_ef)
  end

  defp maybe_filter_course(query, nil), do: query
  defp maybe_filter_course(query, course_id), do: where(query, [c], c.course_id == ^course_id)
end
