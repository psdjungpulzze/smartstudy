defmodule FunSheep.Repo.Migrations.DropEnabledSourcesFromAssessmentSessionStates do
  use Ecto.Migration

  def change do
    alter table(:assessment_session_states) do
      remove :enabled_sources, {:array, :string}
    end
  end
end
