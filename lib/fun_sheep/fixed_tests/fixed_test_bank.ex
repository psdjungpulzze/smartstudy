defmodule FunSheep.FixedTests.FixedTestBank do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_visibility ~w(private shared_link class school)

  schema "fixed_test_banks" do
    field :title, :string
    field :description, :string
    field :visibility, :string, default: "private"
    field :shuffle_questions, :boolean, default: false
    field :time_limit_minutes, :integer
    field :max_attempts, :integer
    field :version, :integer, default: 1
    field :archived_at, :utc_datetime

    belongs_to :created_by, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    has_many :questions, FunSheep.FixedTests.FixedTestQuestion,
      foreign_key: :bank_id,
      preload_order: [asc: :position]

    has_many :assignments, FunSheep.FixedTests.FixedTestAssignment, foreign_key: :bank_id
    has_many :sessions, FunSheep.FixedTests.FixedTestSession, foreign_key: :bank_id

    timestamps(type: :utc_datetime)
  end

  def changeset(bank, attrs) do
    bank
    |> cast(attrs, [
      :title,
      :description,
      :created_by_id,
      :course_id,
      :visibility,
      :shuffle_questions,
      :time_limit_minutes,
      :max_attempts,
      :archived_at
    ])
    |> validate_required([:title, :created_by_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_inclusion(:visibility, @valid_visibility)
    |> validate_number(:time_limit_minutes, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
  end
end
