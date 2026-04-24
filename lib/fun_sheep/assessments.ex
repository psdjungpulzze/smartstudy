defmodule FunSheep.Assessments do
  @moduledoc """
  The Assessments context.

  Manages test scheduling, format templates, and readiness scores.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo

  alias FunSheep.Assessments.{
    TestSchedule,
    TestFormatTemplate,
    ReadinessScore,
    ReadinessCalculator,
    ScopeReadiness
  }

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Assessments.CohortCache
  alias FunSheep.Questions.QuestionAttempt
  alias FunSheep.Workers.AIQuestionGenerationWorker

  @cohort_min_size 20

  ## Test Schedules

  def list_test_schedules do
    Repo.all(TestSchedule)
  end

  def list_test_schedules_by_user(user_role_id) do
    from(ts in TestSchedule,
      where: ts.user_role_id == ^user_role_id,
      order_by: ts.test_date
    )
    |> Repo.all()
  end

  @doc """
  Lists test schedules for a user, preloading course.
  Alias matching the task spec.
  """
  def list_test_schedules_for_user(nil), do: []

  def list_test_schedules_for_user(user_role_id) do
    from(ts in TestSchedule,
      where: ts.user_role_id == ^user_role_id,
      order_by: ts.test_date,
      preload: [:course]
    )
    |> Repo.all()
  end

  def list_test_schedules_for_course(user_role_id, course_id) do
    from(ts in TestSchedule,
      where: ts.user_role_id == ^user_role_id and ts.course_id == ^course_id,
      order_by: ts.test_date,
      preload: [:course]
    )
    |> Repo.all()
  end

  @doc """
  Lists upcoming test schedules (test_date >= today) within `days_ahead` days,
  ordered by test date ascending.
  """
  def list_upcoming_schedules(user_role_id, days_ahead \\ 30) do
    today = Date.utc_today()
    cutoff = Date.add(today, days_ahead)

    from(ts in TestSchedule,
      where:
        ts.user_role_id == ^user_role_id and
          ts.test_date >= ^today and
          ts.test_date <= ^cutoff,
      order_by: [asc: ts.test_date],
      preload: [:course]
    )
    |> Repo.all()
  end

  @doc """
  Returns the student's primary (pinned or nearest-deadline) upcoming test.

  Resolution (per ADR-005):
  1. If `user_roles.pinned_test_schedule_id` is set AND the referenced test
     is still upcoming, that is primary.
  2. Otherwise, the nearest-deadline upcoming test.
  3. Otherwise, `nil`.

  Stale pins (pinned test has passed / been deleted) silently fall through
  to the nearest-deadline default — we do not resurrect an expired pin.
  """
  def primary_test(nil), do: nil

  def primary_test(user_role_id) when is_binary(user_role_id) do
    upcoming = list_upcoming_schedules(user_role_id, 365)
    primary_test_from_upcoming(user_role_id, upcoming)
  end

  @doc """
  Same as `primary_test/1` but takes a pre-fetched upcoming list to avoid
  duplicate queries when the dashboard has already loaded it.
  """
  def primary_test_from_upcoming(nil, _), do: nil
  def primary_test_from_upcoming(_, []), do: nil

  def primary_test_from_upcoming(user_role_id, upcoming) when is_list(upcoming) do
    case Repo.get(UserRole, user_role_id) do
      %UserRole{pinned_test_schedule_id: nil} ->
        List.first(upcoming)

      %UserRole{pinned_test_schedule_id: pinned_id} ->
        Enum.find(upcoming, fn ts -> ts.id == pinned_id end) || List.first(upcoming)

      nil ->
        List.first(upcoming)
    end
  end

  @doc """
  Returns the student's pinned test schedule id, or `nil` if none is
  pinned. This is the raw stored value; callers that want the effective
  primary (honoring stale-pin fallback) should use `primary_test/1`.
  """
  def pinned_test_id(nil), do: nil

  def pinned_test_id(user_role_id) do
    case Repo.get(UserRole, user_role_id) do
      %UserRole{pinned_test_schedule_id: id} -> id
      _ -> nil
    end
  end

  @doc """
  Pins a test as the student's primary. The test must belong to this
  user_role. Returns `{:ok, user_role}` or `{:error, changeset}`.
  """
  def pin_test(user_role_id, test_schedule_id) do
    with %UserRole{} = user_role <- Repo.get(UserRole, user_role_id),
         %TestSchedule{user_role_id: ^user_role_id} <-
           Repo.get(TestSchedule, test_schedule_id) do
      user_role
      |> UserRole.changeset(%{pinned_test_schedule_id: test_schedule_id})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      %TestSchedule{} -> {:error, :forbidden}
    end
  end

  @doc """
  Clears any pinned test; the student falls back to the nearest-deadline
  default.
  """
  def unpin_test(user_role_id) do
    case Repo.get(UserRole, user_role_id) do
      nil ->
        {:error, :not_found}

      user_role ->
        user_role
        |> UserRole.changeset(%{pinned_test_schedule_id: nil})
        |> Repo.update()
    end
  end

  @doc """
  Returns upcoming test schedules grouped by course_id.
  Each entry includes the schedule and its latest readiness score.
  Result: %{course_id => [%{schedule: schedule, readiness: score_or_nil}]}
  """
  def list_upcoming_grouped_by_course(nil), do: %{}

  def list_upcoming_grouped_by_course(user_role_id) do
    today = Date.utc_today()

    schedules =
      from(ts in TestSchedule,
        where: ts.user_role_id == ^user_role_id and ts.test_date >= ^today,
        order_by: [asc: ts.test_date],
        preload: [:course]
      )
      |> Repo.all()

    schedules
    |> Enum.map(fn ts ->
      readiness = latest_readiness(user_role_id, ts.id)
      %{schedule: ts, readiness: readiness}
    end)
    |> Enum.group_by(fn entry -> entry.schedule.course_id end)
  end

  def get_test_schedule!(id), do: Repo.get!(TestSchedule, id)

  @doc """
  Gets a test schedule by ID with preloaded course.
  """
  def get_test_schedule_with_course!(id) do
    TestSchedule
    |> Repo.get!(id)
    |> Repo.preload(:course)
  end

  @doc """
  Creates a test schedule and, on success, ensures every chapter in its scope
  has question generation queued.

  Assessments used to enter the world with a scope whose chapters had no
  questions. The student would then hit `AssessmentLive`, which reactively
  enqueued generation on first visit — giving them a dead-end "Questions not
  ready yet" screen. Queuing at creation time makes generation lead the
  student rather than trail them; `AIQuestionGenerationWorker`'s Oban
  uniqueness (5-min window) prevents this from compounding with the engine's
  reactive enqueue or with repeat creations.
  """
  def create_test_schedule(attrs \\ %{}) do
    with {:ok, schedule} <-
           %TestSchedule{}
           |> TestSchedule.changeset(attrs)
           |> Repo.insert() do
      ensure_generation_queued(schedule)
      {:ok, schedule}
    end
  end

  @doc """
  Classifies the readiness of a test schedule's scope. See
  `FunSheep.Assessments.ScopeReadiness` for the possible return values.
  """
  @spec scope_readiness(TestSchedule.t()) :: ScopeReadiness.readiness()
  def scope_readiness(%TestSchedule{} = schedule), do: ScopeReadiness.check(schedule)

  @doc """
  Enqueues `AIQuestionGenerationWorker` once per chapter that is below the
  readiness threshold. Silent no-op when every chapter already has enough
  questions. Returns the list of chapter IDs that were enqueued (useful for
  tests and for logging).
  """
  @spec ensure_generation_queued(TestSchedule.t()) :: [binary()]
  def ensure_generation_queued(%TestSchedule{} = schedule) do
    missing = ScopeReadiness.chapters_needing_generation(schedule)

    Enum.each(missing, fn chapter_id ->
      AIQuestionGenerationWorker.enqueue(schedule.course_id,
        chapter_id: chapter_id,
        count: 10,
        mode: "from_material"
      )
    end)

    missing
  end

  def update_test_schedule(%TestSchedule{} = test_schedule, attrs) do
    test_schedule
    |> TestSchedule.changeset(attrs)
    |> Repo.update()
  end

  def delete_test_schedule(%TestSchedule{} = test_schedule) do
    Repo.delete(test_schedule)
  end

  def change_test_schedule(%TestSchedule{} = test_schedule, attrs \\ %{}) do
    TestSchedule.changeset(test_schedule, attrs)
  end

  ## Test Format Templates

  def list_test_format_templates do
    Repo.all(TestFormatTemplate)
  end

  def get_test_format_template!(id), do: Repo.get!(TestFormatTemplate, id)

  def create_test_format_template(attrs \\ %{}) do
    %TestFormatTemplate{}
    |> TestFormatTemplate.changeset(attrs)
    |> Repo.insert()
  end

  def update_test_format_template(%TestFormatTemplate{} = template, attrs) do
    template
    |> TestFormatTemplate.changeset(attrs)
    |> Repo.update()
  end

  def delete_test_format_template(%TestFormatTemplate{} = template) do
    Repo.delete(template)
  end

  def change_test_format_template(%TestFormatTemplate{} = template, attrs \\ %{}) do
    TestFormatTemplate.changeset(template, attrs)
  end

  ## Readiness Scores

  def list_readiness_scores do
    Repo.all(ReadinessScore)
  end

  def list_readiness_scores_by_user(user_role_id) do
    from(rs in ReadinessScore,
      where: rs.user_role_id == ^user_role_id,
      preload: [:test_schedule]
    )
    |> Repo.all()
  end

  def get_readiness_score!(id), do: Repo.get!(ReadinessScore, id)

  def get_readiness_score_for_schedule(user_role_id, test_schedule_id) do
    Repo.get_by(ReadinessScore,
      user_role_id: user_role_id,
      test_schedule_id: test_schedule_id
    )
  end

  def create_readiness_score(attrs \\ %{}) do
    %ReadinessScore{}
    |> ReadinessScore.changeset(attrs)
    |> Repo.insert()
  end

  def update_readiness_score(%ReadinessScore{} = readiness_score, attrs) do
    readiness_score
    |> ReadinessScore.changeset(attrs)
    |> Repo.update()
  end

  def delete_readiness_score(%ReadinessScore{} = readiness_score) do
    Repo.delete(readiness_score)
  end

  def change_readiness_score(%ReadinessScore{} = readiness_score, attrs \\ %{}) do
    ReadinessScore.changeset(readiness_score, attrs)
  end

  @doc """
  Calculates readiness scores for a user/test and persists the result.
  Returns {:ok, readiness_score} or {:error, changeset}.
  """
  def calculate_and_save_readiness(user_role_id, test_schedule_id) do
    schedule = get_test_schedule!(test_schedule_id)
    scores = ReadinessCalculator.calculate(user_role_id, schedule)

    create_readiness_score(%{
      user_role_id: user_role_id,
      test_schedule_id: test_schedule_id,
      chapter_scores: scores.chapter_scores,
      topic_scores: scores.topic_scores,
      skill_scores: serialize_skill_scores(scores.skill_scores),
      aggregate_score: scores.aggregate_score,
      calculated_at: DateTime.utc_now()
    })
  end

  defp serialize_skill_scores(skill_scores) when is_map(skill_scores) do
    Map.new(skill_scores, fn {section_id, data} ->
      {section_id, Map.update(data, :status, "insufficient_data", &Atom.to_string/1)}
    end)
  end

  defp serialize_skill_scores(_), do: %{}

  @doc """
  Returns the last `limit` readiness scores for a user+test, ordered by most recent first.
  """
  def list_readiness_history(user_role_id, test_schedule_id, limit \\ 10) do
    from(rs in ReadinessScore,
      where: rs.user_role_id == ^user_role_id and rs.test_schedule_id == ^test_schedule_id,
      order_by: [desc: rs.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns a live-computed readiness score reflecting every recorded attempt.

  Returns an unsaved `%ReadinessScore{}` struct with `:aggregate_score`,
  `:chapter_scores`, and `:topic_scores` populated from the current
  `question_attempts` data. Returns `nil` only when the schedule doesn't exist.

  Snapshots in the `readiness_scores` table are written only by
  `calculate_and_save_readiness/2` and used for trend history.
  """
  def latest_readiness(user_role_id, test_schedule_id) do
    case Repo.get(TestSchedule, test_schedule_id) do
      nil ->
        nil

      schedule ->
        scores = ReadinessCalculator.calculate(user_role_id, schedule)

        %ReadinessScore{
          user_role_id: user_role_id,
          test_schedule_id: test_schedule_id,
          aggregate_score: scores.aggregate_score,
          chapter_scores: scores.chapter_scores,
          topic_scores: scores.topic_scores,
          skill_scores: scores.skill_scores
        }
    end
  end

  @doc """
  Returns the total number of question attempts a user has made against
  questions in the test schedule's scoped chapters.

  Used alongside readiness to show effort (how many questions attempted)
  independent of performance (what % were correct).
  """
  def attempts_count_for_schedule(user_role_id, %TestSchedule{scope: scope}) do
    chapter_ids = (scope || %{}) |> Map.get("chapter_ids", [])
    Questions.count_attempts_in_chapters(user_role_id, chapter_ids)
  end

  def attempts_count_for_schedule(user_role_id, test_schedule_id)
      when is_binary(test_schedule_id) do
    case Repo.get(TestSchedule, test_schedule_id) do
      nil -> 0
      schedule -> attempts_count_for_schedule(user_role_id, schedule)
    end
  end

  ## ── Target Score (Spec §6.1) ─────────────────────────────────────────────

  @doc """
  Sets or updates the joint readiness target for a test schedule.

  `proposer` must be `:student | :guardian` — we record who set it so the
  Phase 3 goal flow can reason about proposals and counter-proposals.

  Returns `{:ok, test_schedule}` or `{:error, changeset}`. The target is
  clamped to [0, 100] by the schema validation.
  """
  def set_target_readiness(%TestSchedule{} = schedule, value, proposer)
      when is_integer(value) and proposer in [:student, :guardian] do
    schedule
    |> TestSchedule.changeset(%{
      target_readiness_score: value,
      target_set_by: proposer,
      target_set_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Clears the joint readiness target on a test schedule. Used when the
  pair decides the target was wrong to set in the first place.
  """
  def clear_target_readiness(%TestSchedule{} = schedule) do
    schedule
    |> TestSchedule.changeset(%{
      target_readiness_score: nil,
      target_set_by: nil,
      target_set_at: nil
    })
    |> Repo.update()
  end

  ## ── Readiness Benchmarking ──────────────────────────────────────────────

  @doc """
  Calculates the percentile rank of a user's readiness score among all students
  who have readiness scores for the same course.

  Returns a map with percentile (0-100), rank, total_students, and score_distribution.
  """
  def readiness_percentile(user_role_id, test_schedule_id) do
    schedule = get_test_schedule!(test_schedule_id)
    my_readiness = latest_readiness(user_role_id, test_schedule_id)
    my_score = if my_readiness, do: my_readiness.aggregate_score, else: 0.0

    # Get all latest readiness scores for the same course (any test schedule)
    all_scores =
      from(rs in ReadinessScore,
        join: ts in TestSchedule,
        on: rs.test_schedule_id == ts.id,
        where: ts.course_id == ^schedule.course_id,
        distinct: rs.user_role_id,
        order_by: [desc: rs.inserted_at],
        select: rs.aggregate_score
      )
      |> Repo.all()

    total = length(all_scores)

    if total <= 1 do
      %{
        percentile: 100,
        rank: 1,
        total_students: max(total, 1),
        my_score: my_score,
        average_score: my_score,
        score_distribution: distribution_buckets(all_scores)
      }
    else
      below_count = Enum.count(all_scores, fn s -> s < my_score end)
      percentile = round(below_count / total * 100)
      rank = Enum.count(all_scores, fn s -> s > my_score end) + 1
      avg = Enum.sum(all_scores) / total

      %{
        percentile: percentile,
        rank: rank,
        total_students: total,
        my_score: my_score,
        average_score: Float.round(avg, 1),
        score_distribution: distribution_buckets(all_scores)
      }
    end
  end

  @doc """
  Returns predicted score range based on readiness score.
  Maps readiness % to likely test score range using a simple model.
  """
  def predicted_score_range(readiness_score) when is_number(readiness_score) do
    # Conservative estimate: readiness correlates with ~80% of actual performance
    base = readiness_score * 0.8
    low = max(0, round(base - 10))
    high = min(100, round(base + 15))
    mid = round((low + high) / 2)

    %{low: low, mid: mid, high: high, confidence: score_confidence(readiness_score)}
  end

  def predicted_score_range(_), do: %{low: 0, mid: 50, high: 100, confidence: :low}

  @doc """
  Returns readiness trend for a user over the last N days.
  Shows the trajectory (improving, declining, stable).
  """
  def readiness_trend(user_role_id, test_schedule_id, days \\ 14) do
    cutoff =
      Date.utc_today()
      |> Date.add(-days)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    scores =
      from(rs in ReadinessScore,
        where:
          rs.user_role_id == ^user_role_id and
            rs.test_schedule_id == ^test_schedule_id and
            rs.inserted_at >= ^cutoff,
        order_by: [asc: rs.inserted_at],
        select: %{score: rs.aggregate_score, date: rs.inserted_at}
      )
      |> Repo.all()

    case scores do
      [] ->
        %{direction: :none, change: 0, scores: []}

      [_single] ->
        %{direction: :stable, change: 0, scores: scores}

      multiple ->
        first = hd(multiple).score
        last = List.last(multiple).score
        change = Float.round(last - first, 1)

        direction =
          cond do
            change > 3 -> :improving
            change < -3 -> :declining
            true -> :stable
          end

        %{direction: direction, change: change, scores: multiple}
    end
  end

  ## ── Topic Mastery Map (Spec §5.3) ───────────────────────────────────────

  @doc """
  Returns a chapter → topics (sections) grid for a given student and test
  schedule, with mastery %, attempt counts, and status per topic.

  Spec §5.3: powers the parent-facing topic-level mastery map and its
  drill-down. "Topic" in the spec maps to `Courses.Section` in the schema.

  No fake data: topics with zero attempts return `status: :insufficient_data`
  and `attempts_count: 0`. Chapters without a recorded scope on the schedule
  are skipped (there is nothing to render).

  ## Returns

      [
        %{
          chapter_id: "...",
          chapter_name: "Fractions",
          topics: [
            %{
              section_id: "...",
              section_name: "Adding fractions",
              accuracy: 82.0,
              attempts_count: 11,
              correct_count: 9,
              status: :mastered | :weak | :probing | :insufficient_data
            },
            ...
          ]
        },
        ...
      ]
  """
  def topic_mastery_map(user_role_id, test_schedule_id)
      when is_binary(user_role_id) and is_binary(test_schedule_id) do
    case Repo.get(TestSchedule, test_schedule_id) do
      nil ->
        []

      %TestSchedule{scope: scope} ->
        chapter_ids = (scope || %{}) |> Map.get("chapter_ids", []) |> List.wrap()
        build_mastery_grid(user_role_id, chapter_ids)
    end
  end

  defp build_mastery_grid(_user_role_id, []), do: []

  defp build_mastery_grid(user_role_id, chapter_ids) do
    chapters = Courses.list_chapters_by_ids(chapter_ids)
    sections = Courses.list_sections_by_chapters(chapter_ids)
    sections_by_chapter = Enum.group_by(sections, & &1.chapter_id)

    Enum.map(chapters, fn chapter ->
      topics =
        sections_by_chapter
        |> Map.get(chapter.id, [])
        |> Enum.map(fn section ->
          attempts = Questions.list_section_attempts(user_role_id, section.id)
          correct = Enum.count(attempts, & &1.is_correct)
          total = length(attempts)

          accuracy =
            if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0

          %{
            section_id: section.id,
            section_name: section.name,
            accuracy: accuracy,
            attempts_count: total,
            correct_count: correct,
            status: FunSheep.Assessments.Mastery.status(attempts)
          }
        end)

      %{
        chapter_id: chapter.id,
        chapter_name: chapter.name,
        topics: topics
      }
    end)
  end

  @doc """
  Returns the most recent `limit` attempts for a student on a single
  topic (section), with the question preloaded.

  Powers the parent §5.3 drill-down modal (last 10 attempts).
  """
  def recent_attempts_for_topic(user_role_id, section_id, limit \\ 10)
      when is_binary(user_role_id) and is_binary(section_id) and is_integer(limit) do
    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where: qa.user_role_id == ^user_role_id and q.section_id == ^section_id,
      order_by: [desc: qa.inserted_at],
      limit: ^limit,
      preload: [question: q]
    )
    |> Repo.all()
  end

  @doc """
  Returns a daily accuracy trend for a single topic (section) over the
  last `days` days. Each bucket is `%{date, accuracy, attempts}`. Days
  with no attempts are omitted (no fake fill).
  """
  def topic_accuracy_trend(user_role_id, section_id, days \\ 30)
      when is_binary(user_role_id) and is_binary(section_id) and is_integer(days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

    from(qa in QuestionAttempt,
      join: q in assoc(qa, :question),
      where:
        qa.user_role_id == ^user_role_id and
          q.section_id == ^section_id and
          qa.inserted_at >= ^cutoff,
      order_by: [asc: qa.inserted_at],
      select: %{
        inserted_at: qa.inserted_at,
        is_correct: qa.is_correct
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn %{inserted_at: ts} -> DateTime.to_date(ts) end)
    |> Enum.map(fn {date, attempts} ->
      correct = Enum.count(attempts, & &1.is_correct)
      total = length(attempts)

      %{
        date: date,
        accuracy: if(total > 0, do: Float.round(correct / total * 100, 1), else: 0.0),
        attempts: total
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  Returns weekly percentile snapshots for the given student + test schedule
  over the last `weeks` ISO-week buckets, oldest first. Each bucket is one
  `%{week_start, percentile, score, rank, total}` map.

  Spec §6.1: sparkline input. Weeks with fewer than 2 cohort students are
  omitted — we do not fabricate a percentile when the denominator is small.
  """
  def readiness_percentile_history(user_role_id, test_schedule_id, weeks \\ 4)
      when is_binary(user_role_id) and is_binary(test_schedule_id) and is_integer(weeks) and
             weeks > 0 do
    schedule = Repo.get(TestSchedule, test_schedule_id)

    case schedule do
      nil ->
        []

      %TestSchedule{course_id: course_id} ->
        now = DateTime.utc_now()
        first_week_start = beginning_of_week(DateTime.add(now, -weeks * 7, :day))

        my_snapshots =
          from(rs in ReadinessScore,
            where:
              rs.user_role_id == ^user_role_id and
                rs.test_schedule_id == ^test_schedule_id and
                rs.inserted_at >= ^first_week_start,
            order_by: [asc: rs.inserted_at],
            select: %{score: rs.aggregate_score, inserted_at: rs.inserted_at}
          )
          |> Repo.all()

        cohort_scores =
          from(rs in ReadinessScore,
            join: ts in TestSchedule,
            on: rs.test_schedule_id == ts.id,
            where: ts.course_id == ^course_id and rs.inserted_at >= ^first_week_start,
            select: %{
              user_role_id: rs.user_role_id,
              score: rs.aggregate_score,
              inserted_at: rs.inserted_at
            }
          )
          |> Repo.all()

        weekly_percentiles(my_snapshots, cohort_scores, weeks)
    end
  end

  defp weekly_percentiles(my_snapshots, cohort_scores, weeks) do
    now = DateTime.utc_now()

    Enum.reduce((weeks - 1)..0//-1, [], fn offset, acc ->
      week_start = beginning_of_week(DateTime.add(now, -offset * 7, :day))
      week_end = DateTime.add(week_start, 7, :day)

      my_score =
        my_snapshots
        |> Enum.filter(&in_bucket?(&1.inserted_at, week_start, week_end))
        |> last_score()

      cohort =
        cohort_scores
        |> Enum.filter(&in_bucket?(&1.inserted_at, week_start, week_end))
        |> Enum.uniq_by(& &1.user_role_id)
        |> Enum.map(& &1.score)

      cond do
        my_score == nil or length(cohort) < 2 ->
          acc

        true ->
          below = Enum.count(cohort, &(&1 < my_score))
          pct = round(below / length(cohort) * 100)
          rank = Enum.count(cohort, &(&1 > my_score)) + 1

          [
            %{
              week_start: DateTime.to_date(week_start),
              percentile: pct,
              score: round(my_score),
              rank: rank,
              total: length(cohort)
            }
            | acc
          ]
      end
    end)
    |> Enum.reverse()
  end

  defp in_bucket?(%DateTime{} = ts, start_ts, end_ts),
    do: DateTime.compare(ts, start_ts) != :lt and DateTime.compare(ts, end_ts) == :lt

  defp last_score([]), do: nil
  defp last_score(list), do: list |> List.last() |> Map.get(:score)

  defp beginning_of_week(%DateTime{} = dt) do
    date = DateTime.to_date(dt)
    dow = Date.day_of_week(date)
    monday = Date.add(date, -(dow - 1))
    DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")
  end

  ## ── Cohort Percentile Bands (Spec §6.3) ─────────────────────────────────

  @doc """
  Returns 25th / 50th / 75th / 90th percentile readiness bands for the given
  course + grade cohort. Only cohorts with at least #{@cohort_min_size}
  students return full bands — smaller cohorts return `:small_cohort` and
  the UI must suppress sub-percentile granularity.

  Cached with a 15-minute TTL to keep the parent-dashboard mount cheap.

  Forbidden (by spec): never expose identifying peer data — no names, no
  ranks within a specific class. Only course × grade aggregates.
  """
  def cohort_percentile_bands(course_id, grade)
      when is_binary(course_id) and is_binary(grade) do
    CohortCache.fetch({course_id, grade}, fn ->
      compute_cohort_percentile_bands(course_id, grade)
    end)
  end

  def cohort_percentile_bands(_, _), do: %{status: :small_cohort, size: 0}

  defp compute_cohort_percentile_bands(course_id, grade) do
    scores =
      from(rs in ReadinessScore,
        join: ts in TestSchedule,
        on: rs.test_schedule_id == ts.id,
        join: ur in UserRole,
        on: rs.user_role_id == ur.id,
        where: ts.course_id == ^course_id and ur.grade == ^grade,
        distinct: rs.user_role_id,
        order_by: [desc: rs.inserted_at],
        select: rs.aggregate_score
      )
      |> Repo.all()

    size = length(scores)

    if size < @cohort_min_size do
      %{status: :small_cohort, size: size}
    else
      %{
        status: :ok,
        size: size,
        p25: percentile(scores, 25),
        p50: percentile(scores, 50),
        p75: percentile(scores, 75),
        p90: percentile(scores, 90)
      }
    end
  end

  defp percentile(scores, pct) when is_list(scores) and is_integer(pct) do
    sorted = Enum.sort(scores)
    # Nearest-rank method; simple and appropriate for a product signal.
    rank = round(pct / 100 * (length(sorted) - 1))
    Enum.at(sorted, rank) |> Float.round(1)
  end

  defp distribution_buckets(scores) do
    buckets = %{
      "0-20" => 0,
      "21-40" => 0,
      "41-60" => 0,
      "61-80" => 0,
      "81-100" => 0
    }

    Enum.reduce(scores, buckets, fn score, acc ->
      bucket =
        cond do
          score <= 20 -> "0-20"
          score <= 40 -> "21-40"
          score <= 60 -> "41-60"
          score <= 80 -> "61-80"
          true -> "81-100"
        end

      Map.update!(acc, bucket, &(&1 + 1))
    end)
  end

  defp score_confidence(readiness) do
    cond do
      readiness >= 80 -> :high
      readiness >= 50 -> :medium
      true -> :low
    end
  end
end
