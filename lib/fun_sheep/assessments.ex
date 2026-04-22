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
    ReadinessCalculator
  }

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Questions.QuestionAttempt

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

  def create_test_schedule(attrs \\ %{}) do
    %TestSchedule{}
    |> TestSchedule.changeset(attrs)
    |> Repo.insert()
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
