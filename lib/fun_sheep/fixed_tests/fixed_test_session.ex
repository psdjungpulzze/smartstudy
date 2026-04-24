defmodule FunSheep.FixedTests.FixedTestSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fixed_test_sessions" do
    field :status, :string, default: "in_progress"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :time_taken_seconds, :integer
    field :score_correct, :integer
    field :score_total, :integer
    field :answers, {:array, :map}
    field :questions_order, {:array, :string}

    belongs_to :bank, FunSheep.FixedTests.FixedTestBank
    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :assignment, FunSheep.FixedTests.FixedTestAssignment

    timestamps(type: :utc_datetime)
  end

  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :bank_id,
      :user_role_id,
      :assignment_id,
      :started_at,
      :questions_order
    ])
    |> validate_required([:bank_id, :user_role_id, :started_at])
    |> put_change(:status, "in_progress")
    |> put_change(:answers, [])
  end

  def answer_changeset(session, attrs) do
    session
    |> cast(attrs, [:answers])
    |> validate_required([:answers])
  end

  def complete_changeset(session, attrs) do
    session
    |> cast(attrs, [:completed_at, :time_taken_seconds, :score_correct, :score_total, :answers])
    |> validate_required([:completed_at, :score_correct, :score_total])
    |> validate_number(:score_correct, greater_than_or_equal_to: 0)
    |> validate_number(:score_total, greater_than_or_equal_to: 0)
    |> put_change(:status, "completed")
  end

  def abandon_changeset(session) do
    change(session, status: "abandoned")
  end

  def answered_question_ids(%__MODULE__{answers: answers}) when is_list(answers) do
    Enum.map(answers, & &1["question_id"])
  end

  def answered_question_ids(_), do: []

  def answer_for(%__MODULE__{answers: answers}, question_id) when is_list(answers) do
    Enum.find(answers, fn a -> a["question_id"] == question_id end)
  end

  def answer_for(_, _), do: nil
end
