defmodule FunSheep.Repo.Migrations.AddAssessmentSessionStates do
  use Ecto.Migration

  def change do
    create table(:assessment_session_states, primary_key: false) do
      add :user_role_id, :string, null: false
      add :schedule_id, :string, null: false
      add :engine_state, :map
      add :question_number, :integer, default: 0
      add :phase, :string
      add :enabled_sources, {:array, :string}
      add :selected_answer, :string
      add :assessment_complete, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assessment_session_states, [:user_role_id, :schedule_id],
             name: :assessment_session_states_pkey
           )
  end
end
