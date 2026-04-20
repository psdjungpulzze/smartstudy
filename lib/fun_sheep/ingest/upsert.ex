defmodule FunSheep.Ingest.Upsert do
  @moduledoc """
  Batched natural-key upserts for ingested rows.

  All institution tables (schools, districts, universities) carry a
  `(source, source_id)` unique index. This module runs
  `Repo.insert_all/3` with `on_conflict: {:replace_all_except, [:id, :inserted_at]}`
  and `conflict_target: {:constraint, ...}` so that re-running an
  ingestion is idempotent — existing rows get updated with the fresh
  attributes, new rows get inserted, and the UUID primary key never
  changes so FKs from user_roles/courses/questions stay intact.
  """

  alias FunSheep.Repo

  @default_batch 500

  @doc """
  Upsert a stream of attribute maps into `schema`.

  Returns `{inserted_count, updated_count}`. Caller is responsible for
  ensuring every map has `:source` and `:source_id` (enforced by the
  unique constraint; we'd crash otherwise).

  Options:
    * `:batch_size` — rows per `insert_all` call, default 500
    * `:conflict_target` — constraint name, default `"<table>_source_pid_index"`
    * `:on_before` — `(rows -> rows)` callback for per-batch enrichment
  """
  @spec run(module(), Enumerable.t(), keyword()) :: {non_neg_integer(), non_neg_integer()}
  def run(schema, stream, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch)
    on_before = Keyword.get(opts, :on_before, & &1)

    conflict_target = Keyword.get(opts, :conflict_target, [:source, :source_id])

    replaceable = replaceable_fields(schema)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    stream
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce({0, 0}, fn batch, {ins, upd} ->
      rows =
        batch
        |> on_before.()
        |> Enum.map(&stamp_timestamps(&1, now))
        |> Enum.map(&add_id_if_missing/1)

      {count, _} =
        Repo.insert_all(schema, rows,
          on_conflict: {:replace, replaceable},
          conflict_target: conflict_target,
          returning: false
        )

      # Postgres `insert_all` returns affected row count which covers both
      # inserts and updates; we don't separate here without a RETURNING,
      # so report everything as "upserted" (inserted+updated combined).
      {ins + count, upd}
    end)
  end

  defp replaceable_fields(schema) do
    schema.__schema__(:fields)
    |> Enum.reject(&(&1 in [:id, :inserted_at]))
    |> Enum.reject(fn field ->
      # Associations (belongs_to) expose the FK field separately; skip virtual/embed keys.
      schema.__schema__(:type, field) == nil
    end)
  end

  defp stamp_timestamps(attrs, now) do
    attrs
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp add_id_if_missing(attrs) do
    Map.put_new_lazy(attrs, :id, &Ecto.UUID.generate/0)
  end
end
