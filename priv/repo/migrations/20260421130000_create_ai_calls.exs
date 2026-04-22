defmodule FunSheep.Repo.Migrations.CreateAiCalls do
  use Ecto.Migration

  def change do
    create table(:ai_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider, :string, null: false
      add :model, :string

      add :assistant_name, :string
      add :source, :string, null: false

      add :prompt_tokens, :integer
      add :completion_tokens, :integer
      add :total_tokens, :integer
      add :token_source, :string, null: false

      add :env, :string, null: false

      add :duration_ms, :integer
      add :status, :string, null: false
      add :error, :text

      add :metadata, :map, default: %{}, null: false

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:ai_calls, [:inserted_at])
    create index(:ai_calls, [:provider, :inserted_at])
    create index(:ai_calls, [:source, :inserted_at])
    create index(:ai_calls, [:env, :inserted_at])
  end
end
