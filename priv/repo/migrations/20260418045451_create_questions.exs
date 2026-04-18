defmodule FunSheep.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create_query =
      "CREATE TYPE question_type AS ENUM ('multiple_choice', 'short_answer', 'free_response', 'true_false')"

    drop_query = "DROP TYPE IF EXISTS question_type"
    execute(create_query, drop_query)

    create_query = "CREATE TYPE difficulty_level AS ENUM ('easy', 'medium', 'hard')"
    drop_query = "DROP TYPE IF EXISTS difficulty_level"
    execute(create_query, drop_query)

    create_if_not_exists table(:questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :answer, :text, null: false
      add :question_type, :question_type, null: false
      add :options, :map
      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :nilify_all)
      add :section_id, references(:sections, type: :binary_id, on_delete: :nilify_all)
      add :school_id, references(:schools, type: :binary_id, on_delete: :nilify_all)
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :source_url, :string
      add :source_page, :integer
      add :is_generated, :boolean, default: false, null: false
      add :hobby_context, :string
      add :difficulty, :difficulty_level, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:questions, [:course_id])
    create_if_not_exists index(:questions, [:chapter_id])
    create_if_not_exists index(:questions, [:section_id])
    create_if_not_exists index(:questions, [:school_id])
    create_if_not_exists index(:questions, [:question_type])
    create_if_not_exists index(:questions, [:difficulty])

    create_if_not_exists table(:question_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question_id, references(:questions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :answer_given, :text, null: false
      add :is_correct, :boolean, null: false
      add :time_taken_seconds, :integer
      add :difficulty_at_attempt, :string

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:question_attempts, [:user_role_id])
    create_if_not_exists index(:question_attempts, [:question_id])
    create_if_not_exists index(:question_attempts, [:user_role_id, :question_id])
  end
end
