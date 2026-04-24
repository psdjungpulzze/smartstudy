defmodule FunSheep.Repo.Migrations.CreateMemorySpans do
  use Ecto.Migration

  def change do
    create table(:memory_spans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :delete_all)
      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all)
      # "question" | "chapter" | "course"
      add :granularity, :string, null: false
      # median decay gap in hours; nil = no decay events yet
      add :span_hours, :integer
      add :decay_event_count, :integer, null: false, default: 0
      # "improving" | "declining" | "stable" | "insufficient_data"
      add :trend, :string
      add :previous_span_hours, :integer
      add :calculated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memory_spans, [:user_role_id, :granularity, :question_id],
             where: "question_id IS NOT NULL",
             name: :memory_spans_user_question_idx
           )

    create unique_index(:memory_spans, [:user_role_id, :granularity, :chapter_id],
             where: "chapter_id IS NOT NULL",
             name: :memory_spans_user_chapter_idx
           )

    create unique_index(:memory_spans, [:user_role_id, :granularity, :course_id],
             where: "chapter_id IS NULL AND question_id IS NULL",
             name: :memory_spans_user_course_idx
           )

    create index(:memory_spans, [:user_role_id, :granularity, :course_id])
  end
end
