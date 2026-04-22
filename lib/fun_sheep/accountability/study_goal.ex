defmodule FunSheep.Accountability.StudyGoal do
  @moduledoc """
  Joint study-goal schema (spec §7.1).

  A parent proposes a goal → student accepts, counter-proposes, or
  declines → only `:active` goals count toward tracking.

  `goal_type` values:

    * `:daily_minutes` — target_value = minutes/day
    * `:weekly_practice_count` — target_value = sessions/week
    * `:target_readiness_score` — target_value = 0..100 readiness
    * `:streak_days` — target_value = streak length (days)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @goal_types [:daily_minutes, :weekly_practice_count, :target_readiness_score, :streak_days]
  @statuses [:proposed, :active, :paused, :achieved, :abandoned]
  @proposers [:guardian, :student]

  schema "study_goals" do
    field :goal_type, Ecto.Enum, values: @goal_types
    field :target_value, :integer
    field :start_date, :date
    field :end_date, :date
    field :status, Ecto.Enum, values: @statuses, default: :proposed
    field :proposed_by, Ecto.Enum, values: @proposers
    field :accepted_at, :utc_datetime
    field :decline_reason, :string

    belongs_to :student, FunSheep.Accounts.UserRole
    belongs_to :guardian, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :test_schedule, FunSheep.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  def goal_types, do: @goal_types
  def statuses, do: @statuses

  @doc false
  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [
      :student_id,
      :guardian_id,
      :course_id,
      :test_schedule_id,
      :goal_type,
      :target_value,
      :start_date,
      :end_date,
      :status,
      :proposed_by,
      :accepted_at,
      :decline_reason
    ])
    |> validate_required([
      :student_id,
      :guardian_id,
      :goal_type,
      :target_value,
      :start_date,
      :proposed_by,
      :status
    ])
    |> validate_number(:target_value, greater_than: 0)
    |> validate_target_range()
    |> validate_date_order()
    |> foreign_key_constraint(:student_id)
    |> foreign_key_constraint(:guardian_id)
  end

  defp validate_target_range(changeset) do
    case get_field(changeset, :goal_type) do
      :target_readiness_score ->
        validate_number(changeset, :target_value,
          greater_than_or_equal_to: 1,
          less_than_or_equal_to: 100
        )

      :daily_minutes ->
        validate_number(changeset, :target_value,
          greater_than: 0,
          less_than_or_equal_to: 300
        )

      _ ->
        changeset
    end
  end

  defp validate_date_order(changeset) do
    start = get_field(changeset, :start_date)
    finish = get_field(changeset, :end_date)

    if start && finish && Date.compare(finish, start) == :lt do
      add_error(changeset, :end_date, "must be on or after start_date")
    else
      changeset
    end
  end
end
