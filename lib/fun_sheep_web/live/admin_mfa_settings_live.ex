defmodule FunSheepWeb.AdminMfaSettingsLive do
  @moduledoc """
  MFA settings page for admins.

  Flow:
    1. On mount, ask Interactor for the current user's profile and render
       whether MFA is already enabled.
    2. "Enable" click → POST to Interactor's user MFA enable endpoint, which
       returns an `otpauth_uri` + secret. Render QR code + code entry form.
    3. User types a code → POST to `/verify`; on success, show recovery codes.

  The Interactor user-side enrollment endpoints are not documented in our
  local copy of `08-mfa.md` (only admin endpoints are). We attempt the
  natural mirror path; if Interactor responds 404/405, the UI tells the
  admin to configure MFA through Interactor's hosted console instead.
  """
  use FunSheepWeb, :live_view

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user_token = session["user_token"]

    {:ok,
     socket
     |> assign(:page_title, "Two-factor · Admin")
     |> assign(:user_token, user_token)
     |> assign(:step, :idle)
     |> assign(:enrolled?, nil)
     |> assign(:error, nil)
     |> assign(:otpauth_uri, nil)
     |> assign(:secret, nil)
     |> assign(:code, "")
     |> assign(:recovery_codes, nil)
     |> load_status()}
  end

  @impl true
  def handle_event("start_enroll", _, socket) do
    socket = assign(socket, error: nil)

    case api_enable(socket) do
      {:ok, %{"otpauth_uri" => uri, "secret" => secret}} ->
        {:noreply,
         socket
         |> assign(:step, :verify)
         |> assign(:otpauth_uri, uri)
         |> assign(:secret, secret)}

      {:error, :unsupported} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Interactor did not accept the enrollment request. Please enroll MFA via Interactor's console; once enabled there, it will be enforced on login here automatically."
         )}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("validate", %{"mfa" => %{"code" => code}}, socket) do
    {:noreply, assign(socket, code: code, error: nil)}
  end

  def handle_event("verify", %{"mfa" => %{"code" => code}}, socket) do
    case api_verify(socket, code) do
      {:ok, %{"recovery_codes" => codes}} ->
        {:noreply,
         socket
         |> assign(:step, :done)
         |> assign(:recovery_codes, codes)
         |> assign(:enrolled?, true)}

      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:step, :done)
         |> assign(:enrolled?, true)}

      {:error, message} ->
        {:noreply, assign(socket, error: message, code: "")}
    end
  end

  def handle_event("cancel", _, socket) do
    {:noreply,
     socket
     |> assign(:step, :idle)
     |> assign(:otpauth_uri, nil)
     |> assign(:secret, nil)
     |> assign(:code, "")
     |> assign(:error, nil)}
  end

  ## Private

  # On initial load we don't want to show a scary error if Interactor is
  # unreachable (dev, missing user_token, token-less test). Default to
  # `not enrolled` so the admin sees the Enable button; surface errors only
  # for user-initiated enroll/verify attempts.
  defp load_status(socket) do
    case api_profile(socket) do
      {:ok, %{"mfa_enabled" => true}} -> assign(socket, :enrolled?, true)
      {:ok, _} -> assign(socket, :enrolled?, false)
      {:error, _} -> assign(socket, :enrolled?, false)
    end
  end

  defp api_profile(socket) do
    user = socket.assigns.current_user
    org = user["org"] || default_org()
    sub = user["interactor_user_id"]

    request(socket, :get, "/api/v1/orgs/#{org}/users/#{sub}", nil)
  end

  defp api_enable(socket) do
    user = socket.assigns.current_user
    org = user["org"] || default_org()
    sub = user["interactor_user_id"]

    case request(socket, :post, "/api/v1/orgs/#{org}/users/#{sub}/mfa/enable", %{}) do
      {:ok, body} -> {:ok, body}
      {:error, :not_found} -> {:error, :unsupported}
      {:error, :method_not_allowed} -> {:error, :unsupported}
      other -> other
    end
  end

  defp api_verify(socket, code) do
    user = socket.assigns.current_user
    org = user["org"] || default_org()
    sub = user["interactor_user_id"]

    request(socket, :post, "/api/v1/orgs/#{org}/users/#{sub}/mfa/verify", %{code: code})
  end

  defp request(socket, method, path, body) do
    token = socket.assigns.user_token
    url = interactor_url() <> path
    headers = if token, do: [{"authorization", "Bearer #{token}"}], else: []

    response =
      case method do
        :get -> Req.get(url, headers: headers)
        :post -> Req.post(url, headers: headers, json: body || %{})
      end

    case response do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 201, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 405}} ->
        {:error, :method_not_allowed}

      {:ok, %{status: 401}} ->
        {:error, "Not authorized — try signing in again."}

      {:ok, %{status: status, body: body}} ->
        {:error, "Interactor returned #{status}: #{extract_error_message(body)}"}

      {:error, reason} ->
        Logger.error("MFA API error: #{inspect(reason)}")
        {:error, "Network error contacting Interactor."}
    end
  end

  defp extract_error_message(%{"error" => msg}) when is_binary(msg), do: msg
  defp extract_error_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_error_message(body) when is_map(body), do: inspect(body)
  defp extract_error_message(_), do: "(no message)"

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp default_org, do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-2xl mx-auto">
      <h1 class="text-2xl font-bold text-[#1C1C1E] mb-2">Two-factor authentication</h1>
      <p class="text-sm text-[#8E8E93] mb-6">
        Protect your admin account with a TOTP authenticator app like Google
        Authenticator, 1Password, or Authy.
      </p>

      <div
        :if={@error}
        role="alert"
        class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm mb-4"
      >
        {@error}
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6">
        <%!-- Status --%>
        <div :if={@step == :idle and @enrolled? == true}>
          <div class="flex items-center gap-3 mb-4">
            <span class="inline-block w-2 h-2 rounded-full bg-[#4CD964]"></span>
            <span class="text-sm font-medium text-[#1C1C1E]">MFA is enabled on this account.</span>
          </div>
          <p class="text-sm text-[#8E8E93]">
            To disable or regenerate recovery codes, use Interactor's admin console.
          </p>
        </div>

        <div :if={@step == :idle and @enrolled? == false}>
          <div class="flex items-center gap-3 mb-4">
            <span class="inline-block w-2 h-2 rounded-full bg-[#FFCC00]"></span>
            <span class="text-sm font-medium text-[#1C1C1E]">MFA is not enabled.</span>
          </div>
          <button
            type="button"
            phx-click="start_enroll"
            class="px-6 py-2 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium shadow-md"
          >
            Enable MFA
          </button>
        </div>

        <div :if={@step == :idle and is_nil(@enrolled?)}>
          <p class="text-sm text-[#8E8E93]">Loading status…</p>
        </div>

        <%!-- Verify --%>
        <div :if={@step == :verify}>
          <h2 class="text-lg font-semibold text-[#1C1C1E] mb-3">Add this to your app</h2>
          <p class="text-sm text-[#8E8E93] mb-4">
            Open your authenticator app and add this account, then enter the 6-digit code it generates.
          </p>

          <div class="space-y-3 mb-6">
            <%!-- On mobile the otpauth:// link deep-links into the installed authenticator.
                 The secret is never sent to any third-party QR service — we display it
                 directly so the admin can scan it from a trusted source (their own screen). --%>
            <a
              href={@otpauth_uri}
              class="block px-4 py-3 rounded-xl bg-[#E8F8EB] text-[#1C1C1E] text-sm font-medium text-center hover:bg-[#D4F5DA]"
            >
              📱 Open in authenticator app
            </a>

            <div class="bg-[#F5F5F7] rounded-xl p-4">
              <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium mb-1">
                Or enter this secret manually
              </div>
              <div class="font-mono text-[#1C1C1E] text-sm break-all select-all">{@secret}</div>
            </div>
          </div>

          <form phx-change="validate" phx-submit="verify" class="space-y-3">
            <input
              type="text"
              name="mfa[code]"
              value={@code}
              placeholder="123456"
              inputmode="numeric"
              pattern="[0-9]*"
              autocomplete="one-time-code"
              autofocus
              maxlength="8"
              class="w-full px-4 py-3 text-center tracking-[0.5em] font-mono text-xl bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none"
            />
            <div class="flex items-center gap-2">
              <button
                type="submit"
                class="flex-1 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md"
              >
                Verify and enable
              </button>
              <button
                type="button"
                phx-click="cancel"
                class="px-4 py-3 rounded-full border border-[#E5E5EA] text-[#1C1C1E] font-medium hover:bg-[#F5F5F7]"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>

        <%!-- Done --%>
        <div :if={@step == :done}>
          <div class="flex items-center gap-3 mb-4">
            <span class="inline-block w-2 h-2 rounded-full bg-[#4CD964]"></span>
            <span class="text-sm font-medium text-[#1C1C1E]">MFA enabled.</span>
          </div>

          <div :if={@recovery_codes}>
            <p class="text-sm text-[#1C1C1E] font-medium mb-2">Save your recovery codes</p>
            <p class="text-xs text-[#8E8E93] mb-3">
              Store these somewhere safe. Each code can be used once if you lose access to your authenticator app.
            </p>
            <ul class="font-mono text-sm bg-[#F5F5F7] rounded-xl p-4 grid grid-cols-2 gap-y-1">
              <li :for={code <- @recovery_codes}>{code}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

end
