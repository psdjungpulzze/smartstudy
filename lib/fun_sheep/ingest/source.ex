defmodule FunSheep.Ingest.Source do
  @moduledoc """
  Behaviour implemented by each registry-specific ingester.

  Every source module must declare a stable `source/0` string (this is the
  value persisted in `schools.source`, `districts.source`, etc.) and a
  `run/2` function that downloads, parses, and upserts one dataset.
  """

  @type dataset :: String.t()
  @type stats :: %{required(atom()) => term()}

  @callback source() :: String.t()
  @callback datasets() :: [dataset()]
  @callback run(dataset(), keyword()) :: {:ok, stats()} | {:error, term()}
end
