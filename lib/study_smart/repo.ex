defmodule StudySmart.Repo do
  use Ecto.Repo,
    otp_app: :study_smart,
    adapter: Ecto.Adapters.Postgres
end
