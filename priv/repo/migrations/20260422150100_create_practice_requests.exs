defmodule FunSheep.Repo.Migrations.CreatePracticeRequests do
  use Ecto.Migration

  def change do
    create table(:practice_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :student_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :guardian_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      add :reason_code, :string, null: false
      add :reason_text, :text
      add :status, :string, null: false, default: "pending"

      add :sent_at, :utc_datetime, null: false
      add :viewed_at, :utc_datetime
      add :decided_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false

      add :parent_note, :text
      add :reminder_sent_at, :utc_datetime

      # §4.6, §8.2: immutable activity snapshot at request time so emails render
      # from stable data even if activity changes later.
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:practice_requests, [:student_id, :status])
    create index(:practice_requests, [:guardian_id, :status])
    create index(:practice_requests, [:expires_at])

    # §4.11: one :pending request per student at a time.
    create unique_index(:practice_requests, [:student_id],
             where: "status = 'pending'",
             name: :practice_requests_one_pending_per_student
           )
  end
end
