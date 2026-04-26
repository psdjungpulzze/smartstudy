defmodule FunSheep.Assessments.ExamSimulationSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(in_progress submitted timed_out abandoned)

  schema "exam_simulation_sessions" do
    field :status, :string, default: "in_progress"
    field :time_limit_seconds, :integer
    field :started_at, :utc_datetime
    field :submitted_at, :utc_datetime
    # Flat ordered list of question UUIDs
    field :question_ids_order, {:array, :string}, default: []
    # [%{"name" => name, "question_count" => n, "time_budget_seconds" => s, "start_index" => i}]
    field :section_boundaries, {:array, :map}, default: []
    # %{question_id => %{"answer" => "...", "flagged" => false, "time_spent_seconds" => 12}}
    field :answers, :map, default: %{}
    field :score_correct, :integer
    field :score_total, :integer
    field :score_pct, :float
    # %{section_name => %{"correct" => 3, "total" => 5, "time_seconds" => 240}}
    field :section_scores, :map

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :schedule, FunSheep.Assessments.TestSchedule, foreign_key: :schedule_id
    belongs_to :format_template, FunSheep.Assessments.TestFormatTemplate

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :user_role_id, :course_id, :schedule_id, :format_template_id,
      :status, :time_limit_seconds, :started_at, :submitted_at,
      :question_ids_order, :section_boundaries, :answers,
      :score_correct, :score_total, :score_pct, :section_scores
    ])
    |> validate_required([:user_role_id, :course_id, :time_limit_seconds, :started_at, :question_ids_order])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end

  def answer_changeset(session, answers) do
    change(session, answers: answers)
  end

  def submit_changeset(session, attrs) do
    session
    |> cast(attrs, [:score_correct, :score_total, :score_pct, :section_scores, :submitted_at])
    |> put_change(:status, "submitted")
  end

  def timeout_changeset(session, attrs) do
    session
    |> cast(attrs, [:score_correct, :score_total, :score_pct, :section_scores, :submitted_at])
    |> put_change(:status, "timed_out")
  end

  def abandoned_changeset(session) do
    change(session, status: "abandoned")
  end
end
