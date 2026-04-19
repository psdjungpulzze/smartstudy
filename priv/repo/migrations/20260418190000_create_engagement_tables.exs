defmodule FunSheep.Repo.Migrations.CreateEngagementTables do
  use Ecto.Migration

  def change do
    # ── Review Cards (Spaced Repetition) ────────────────────────────────────
    create table(:review_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false

      # SM-2 algorithm fields
      add :ease_factor, :float, default: 2.5, null: false
      add :interval_days, :float, default: 0.0, null: false
      add :repetitions, :integer, default: 0, null: false
      add :next_review_at, :utc_datetime, null: false
      add :last_reviewed_at, :utc_datetime
      # new | learning | review | graduated
      add :status, :string, default: "new", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:review_cards, [:user_role_id])
    create index(:review_cards, [:user_role_id, :next_review_at])
    create index(:review_cards, [:user_role_id, :course_id])
    create unique_index(:review_cards, [:user_role_id, :question_id])

    # ── Daily Challenges ────────────────────────────────────────────────────
    create table(:daily_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :challenge_date, :date, null: false
      add :question_ids, {:array, :binary_id}, default: [], null: false
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_challenges, [:challenge_date, :course_id])

    # ── Daily Challenge Attempts ────────────────────────────────────────────
    create table(:daily_challenge_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :daily_challenge_id,
          references(:daily_challenges, type: :binary_id, on_delete: :delete_all),
          null: false

      # %{question_id => %{answer, is_correct, time_ms}}
      add :answers, :map, default: %{}, null: false
      add :score, :integer, default: 0, null: false
      add :total_time_ms, :integer, default: 0, null: false
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_challenge_attempts, [:user_role_id, :daily_challenge_id])
    create index(:daily_challenge_attempts, [:daily_challenge_id])

    # ── Study Sessions (for receipts + tracking) ────────────────────────────
    create table(:study_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)

      # review | practice | assessment | quick_test | daily_challenge | just_this
      add :session_type, :string, null: false
      add :questions_attempted, :integer, default: 0, null: false
      add :questions_correct, :integer, default: 0, null: false
      add :duration_seconds, :integer, default: 0, null: false
      add :xp_earned, :integer, default: 0, null: false
      add :readiness_before, :float
      add :readiness_after, :float
      add :topics_covered, {:array, :string}, default: []
      # morning | afternoon | evening | night
      add :time_window, :string
      add :completed_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:study_sessions, [:user_role_id])
    create index(:study_sessions, [:user_role_id, :inserted_at])
    create index(:study_sessions, [:user_role_id, :session_type])

    # ── Proof Cards (shareable progress snapshots) ──────────────────────────
    create table(:proof_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all)
      add :test_schedule_id, references(:test_schedules, type: :binary_id, on_delete: :delete_all)

      # readiness_jump | streak_milestone | weekly_rank | test_complete
      add :card_type, :string, null: false
      add :title, :string, null: false
      # %{before: 45, after: 72, percentile: 85}
      add :metrics, :map, default: %{}, null: false
      # unique token for public sharing
      add :share_token, :string, null: false
      add :shared_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:proof_cards, [:share_token])
    create index(:proof_cards, [:user_role_id])
  end
end
