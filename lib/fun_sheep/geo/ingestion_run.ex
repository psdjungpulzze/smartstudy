defmodule FunSheep.Geo.IngestionRun do
  @moduledoc """
  Audit record for a single ingestion attempt.

  One row per source+dataset+start-time. Tracks row counts, errors, and the
  GCS object key of the cached raw payload so we can reproduce or diff runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending downloading parsing upserting completed failed)

  schema "ingestion_runs" do
    field :source, :string
    field :dataset, :string
    field :status, :string, default: "pending"
    field :object_key, :string
    field :row_count, :integer
    field :inserted_count, :integer
    field :updated_count, :integer
    field :error_count, :integer
    field :error_sample, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :source,
      :dataset,
      :status,
      :object_key,
      :row_count,
      :inserted_count,
      :updated_count,
      :error_count,
      :error_sample,
      :started_at,
      :finished_at,
      :metadata
    ])
    |> validate_required([:source, :dataset, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
