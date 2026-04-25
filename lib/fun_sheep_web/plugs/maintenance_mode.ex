defmodule FunSheepWeb.Plugs.MaintenanceMode do
  @moduledoc """
  When the `maintenance_mode` feature flag is ON, returns a 503 for every
  non-admin route. Admin routes (`/admin/*`) stay reachable so operators
  can turn the flag back off without climbing through a shell.

  Mount this plug in `FunSheepWeb.Endpoint` *after* `Plug.Session` and
  *before* `Plug.Router`.

  Exempt paths (always allowed through):
    * `/admin/*`          — admin needs to toggle the flag
    * `/auth/*`           — admins need to log in
    * `/health`           — Cloud Run readiness probe
    * `/dev/*`            — dev-only login shortcut
    * `/api/webhooks/*`   — Interactor can still deliver events
  """

  import Plug.Conn

  @exempt_prefixes ~w(/admin /auth /health /dev /api/webhooks)

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      exempt?(conn.request_path) -> conn
      maintenance_on?() -> send_503(conn)
      true -> conn
    end
  end

  defp exempt?(path) when is_binary(path) do
    Enum.any?(@exempt_prefixes, &String.starts_with?(path, &1))
  end

  defp maintenance_on? do
    # maintenance_mode defaults to OFF — only block traffic when explicitly enabled.
    # If FunWithFlags can't reach the DB (test env without sandbox, or DB down),
    # treat as disabled so the site stays up.
    FunWithFlags.enabled?(:maintenance_mode)
  rescue
    _ -> false
  end

  defp send_503(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(503, body())
    |> halt()
  end

  defp body do
    """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>Maintenance</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
        background:#F5F5F7;color:#1C1C1E;margin:0;display:flex;align-items:center;
        justify-content:center;min-height:100vh;padding:24px}
      .card{background:#fff;border-radius:16px;padding:32px;max-width:480px;
        box-shadow:0 4px 12px rgba(0,0,0,0.08)}
      h1{margin:0 0 8px 0;font-size:24px}
      p{margin:0;color:#8E8E93;line-height:1.5}
    </style></head><body>
    <div class="card">
      <h1>🛠 We'll be right back.</h1>
      <p>FunSheep is temporarily down for maintenance. Please try again in a few minutes.</p>
    </div></body></html>
    """
  end
end
