defmodule FunSheep.Courses.KnownTestDate do
  @moduledoc """
  Official test dates sourced from organizing bodies (College Board, ACT, ETS, etc.)

  Populated quarterly by TestDateSyncWorker via Anthropic web search.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_test_types ~w(sat act ap ib hsc clt lsat bar gmat mcat gre)

  schema "known_test_dates" do
    field :test_type, :string
    field :test_name, :string
    field :test_date, :date
    field :registration_deadline, :date
    field :late_registration_deadline, :date
    field :score_release_date, :date
    field :source_url, :string
    field :region, :string, default: "us"
    field :last_synced_at, :utc_datetime

    has_many :test_schedules, FunSheep.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(known_test_date, attrs) do
    known_test_date
    |> cast(attrs, [
      :test_type,
      :test_name,
      :test_date,
      :registration_deadline,
      :late_registration_deadline,
      :score_release_date,
      :source_url,
      :region,
      :last_synced_at
    ])
    |> validate_required([:test_type, :test_name, :test_date])
    |> validate_inclusion(:test_type, @valid_test_types)
    |> unique_constraint([:test_type, :test_date, :region])
  end
end
