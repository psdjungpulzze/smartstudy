defmodule FunSheep.AIUsage.Call do
  @moduledoc """
  Record of a single LLM call, persisted for token-usage telemetry.

  Populated by `FunSheep.AIUsage.log_call/1`, typically via the instrumented
  `FunSheep.Interactor.Agents.chat/3` wrapper.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(openai anthropic google interactor unknown)
  @token_sources ~w(interactor estimated)
  @statuses ~w(ok error timeout)

  schema "ai_calls" do
    field :provider, :string
    field :model, :string
    field :assistant_name, :string
    field :source, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
    field :token_source, :string
    field :env, :string
    field :duration_ms, :integer
    field :status, :string
    field :error, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required ~w(provider source token_source env status)a
  @optional ~w(model assistant_name prompt_tokens completion_tokens total_tokens duration_ms error metadata)a

  def changeset(call, attrs) do
    call
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:token_source, @token_sources)
    |> validate_inclusion(:status, @statuses)
  end
end
