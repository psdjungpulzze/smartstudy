defmodule FunSheep.RepoRead do
  @moduledoc """
  Read-only Ecto repo pointed at the read replica when DATABASE_READ_URL is set,
  falling back to the primary when it isn't. Use this for heavy read queries
  (leaderboards, cohort percentiles, course browsing) to offload the primary.

  Drop-in replacement for FunSheep.Repo on read paths:

      FunSheep.RepoRead.all(query)
      FunSheep.RepoRead.get_by(Schema, field: value)
  """

  use Ecto.Repo,
    otp_app: :fun_sheep,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
