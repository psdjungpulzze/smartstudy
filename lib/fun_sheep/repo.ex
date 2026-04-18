defmodule FunSheep.Repo do
  use Ecto.Repo,
    otp_app: :fun_sheep,
    adapter: Ecto.Adapters.Postgres
end
