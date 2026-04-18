defmodule StudySmart.Assessments do
  @moduledoc """
  The Assessments context.

  Manages test scheduling, format templates, and readiness scores.
  """

  import Ecto.Query, warn: false
  alias StudySmart.Repo

  alias StudySmart.Assessments.{
    TestSchedule,
    TestFormatTemplate,
    ReadinessScore,
    ReadinessCalculator
  }

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
  def list_test_schedules_for_user(user_role_id) do
    from(ts in TestSchedule,
      where: ts.user_role_id == ^user_role_id,
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
      aggregate_score: scores.aggregate_score,
      calculated_at: DateTime.utc_now()
    })
  end

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
  Returns the most recent readiness score for a user+test, or nil.
  """
  def latest_readiness(user_role_id, test_schedule_id) do
    from(rs in ReadinessScore,
      where: rs.user_role_id == ^user_role_id and rs.test_schedule_id == ^test_schedule_id,
      order_by: [desc: rs.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end
end
