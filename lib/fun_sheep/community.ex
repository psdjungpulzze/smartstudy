defmodule FunSheep.Community do
  @moduledoc """
  The Community context.

  Manages community-driven quality signals for content: likes, dislikes,
  quality scores, visibility states, and dormant content detection.

  Quality scores are computed purely from real interaction data — no fake
  or pre-seeded values. Scores start at 0.0 and grow only as real users
  interact with content.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Community.ContentLike
  alias FunSheep.Courses.Course

  ## Like / Dislike reactions

  @doc """
  Records a user's reaction to a course.

  Idempotent — if the user has already reacted, updates their existing
  reaction. Triggers a quality score recomputation after saving.

  Returns `{:ok, reaction}` on success or `{:error, changeset}` on failure.
  """
  def react_to_course(user_role_id, course_id, reaction)
      when reaction in ["like", "dislike"] do
    existing = Repo.get_by(ContentLike, user_role_id: user_role_id, course_id: course_id)

    result =
      if existing do
        existing
        |> ContentLike.changeset(%{reaction: reaction})
        |> Repo.update()
      else
        %ContentLike{}
        |> ContentLike.changeset(%{
          user_role_id: user_role_id,
          course_id: course_id,
          reaction: reaction
        })
        |> Repo.insert()
      end

    case result do
      {:ok, _} ->
        recompute_course_quality_score(course_id)
        {:ok, reaction}

      error ->
        error
    end
  end

  @doc """
  Returns the current user's reaction to a course, or `nil` if none.
  """
  def get_user_reaction(user_role_id, course_id) do
    case Repo.get_by(ContentLike, user_role_id: user_role_id, course_id: course_id) do
      nil -> nil
      like -> like.reaction
    end
  end

  ## Quality score computation

  @doc """
  Computes and persists the quality score for a course.

  Formula:
    base_engagement  = (attempt_count × 1.0) + (unique_user_count × 0.5)
    completion_bonus = completion_count × 5.0
    like_score       = (likes × 2.0) - (dislikes × 1.0)
    quality_score    = base_engagement + completion_bonus + like_score

  Also updates `like_count`, `dislike_count`, `visibility_state`, and
  `quality_last_computed_at`.
  """
  def recompute_course_quality_score(course_id) do
    course = FunSheep.Courses.get_course!(course_id)

    likes =
      Repo.aggregate(
        from(l in ContentLike, where: l.course_id == ^course_id and l.reaction == "like"),
        :count
      )

    dislikes =
      Repo.aggregate(
        from(l in ContentLike, where: l.course_id == ^course_id and l.reaction == "dislike"),
        :count
      )

    attempt_count = course.attempt_count || 0
    unique_users = course.unique_user_count || 0
    completions = course.completion_count || 0

    base_engagement = attempt_count * 1.0 + unique_users * 0.5
    completion_bonus = completions * 5.0
    like_score = likes * 2.0 - dislikes * 1.0
    quality_score = base_engagement + completion_bonus + like_score

    visibility_state = compute_visibility_state(quality_score, attempt_count, course.inserted_at)

    course
    |> Course.changeset(%{
      quality_score: quality_score,
      like_count: likes,
      dislike_count: dislikes,
      quality_last_computed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      visibility_state: visibility_state
    })
    |> Repo.update()
  end

  defp compute_visibility_state(score, attempt_count, inserted_at) do
    hours_old = DateTime.diff(DateTime.utc_now(), inserted_at, :hour)

    cond do
      # New content gets a 72-hour boost window to surface to users
      hours_old < 72 -> "boosted"
      score > 100 -> "boosted"
      score < -10 and attempt_count > 20 -> "flagged"
      score < 0 and attempt_count > 20 -> "reduced"
      true -> "normal"
    end
  end

  @doc """
  Returns a velocity-boosted ranking score for a course.

  New courses receive a multiplier that decays over 72 hours.
  Old courses with zero engagement also decay via a weekly recency factor.

  Used for ordering search/browse results.
  """
  def ranking_score(%Course{} = course) do
    base_score = course.quality_score || 0.0
    hours_old = DateTime.diff(DateTime.utc_now(), course.inserted_at, :hour)

    velocity_multiplier =
      cond do
        hours_old < 24 -> 1.5
        hours_old < 48 -> 1.25
        hours_old < 72 -> 1.1
        true -> 1.0
      end

    # Apply recency decay for old content with no engagement
    weeks_old = div(hours_old, 168)

    recency_factor =
      if weeks_old > 1 and (course.attempt_count || 0) == 0 do
        :math.pow(0.95, weeks_old)
      else
        1.0
      end

    base_score * velocity_multiplier * recency_factor
  end

  ## Course engagement tracking

  @doc """
  Records a course completion (called when a student finishes a full test
  end-to-end). Increments `completion_count` and triggers quality score
  recomputation.
  """
  def record_course_completion(course_id, _user_role_id) do
    from(c in Course, where: c.id == ^course_id)
    |> Repo.update_all(inc: [completion_count: 1])

    recompute_course_quality_score(course_id)
    :ok
  end

  @doc """
  Increments the attempt counter for a course.

  Called when new question attempts are recorded for questions in this course.
  """
  def update_course_engagement(course_id) do
    from(c in Course, where: c.id == ^course_id)
    |> Repo.update_all(inc: [attempt_count: 1])

    :ok
  end

  ## Dormant content detection

  @doc """
  Marks courses as dormant when they have had no question attempts in 90 days.

  Sets `visibility_state` to `"reduced"` and records `dormant_at`.
  Intended to run nightly via an Oban cron job.
  """
  def mark_dormant_courses do
    cutoff = DateTime.add(DateTime.utc_now(), -90, :day)

    from(c in Course,
      where:
        c.inserted_at < ^cutoff and
          (is_nil(c.quality_last_computed_at) or c.quality_last_computed_at < ^cutoff) and
          c.visibility_state != "delisted" and
          c.attempt_count == 0
    )
    |> Repo.update_all(
      set: [
        visibility_state: "reduced",
        dormant_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end
end
