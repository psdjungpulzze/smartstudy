defmodule FunSheepWeb.LoginLive do
  @moduledoc """
  Custom login screen with role selection.

  Flow:
  1. User picks the role they are signing in as (Student default; Teacher/Parent secondary).
  2. User submits username + password.
  3. We authenticate against Interactor `/api/v1/users/login`.
  4. We hand the JWT + selected role to `/auth/session`, which resolves or
     creates the local `UserRole(interactor_user_id, role)` and sets the session.
  """

  use FunSheepWeb, :live_view

  require Logger

  @roles ~w(student teacher parent)
  @default_role "student"

  @impl true
  def mount(params, session, socket) do
    if session["current_user"] || session["dev_user"] do
      user = session["current_user"] || session["dev_user"]
      role = user["role"] || @default_role
      {:ok, redirect(socket, to: redirect_path(role))}
    else
      admin_mode = socket.assigns[:live_action] == :admin
      initial_role = normalize_role(params["role"]) || @default_role

      {:ok,
       socket
       |> assign(:page_title, if(admin_mode, do: "Sign in", else: "Sign in"))
       |> assign(:admin_mode, admin_mode)
       |> assign(:role, initial_role)
       |> assign(:form, %{"username" => "", "password" => ""})
       |> assign(:error, nil)
       |> assign(:loading, false)
       |> assign(:step, :credentials)
       |> assign(:mfa_session_token, nil)
       |> assign(:mfa_code, ""), layout: false}
    end
  end

  @impl true
  def handle_event("select_role", %{"role" => role}, socket) do
    case normalize_role(role) do
      nil -> {:noreply, socket}
      r -> {:noreply, assign(socket, role: r, error: nil)}
    end
  end

  @impl true
  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign(socket, form: params, error: nil)}
  end

  @impl true
  def handle_event("login", %{"login" => params}, socket) do
    socket = assign(socket, loading: true, error: nil)

    case authenticate(params["username"], params["password"]) do
      {:ok, :tokens, tokens} ->
        finish_login(socket, tokens)

      {:ok, :mfa_required, session_token} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:step, :mfa)
         |> assign(:mfa_session_token, session_token)
         |> assign(:mfa_code, "")
         |> assign(:error, nil)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, message)}
    end
  end

  def handle_event("mfa_validate", %{"mfa" => %{"code" => code}}, socket) do
    {:noreply, assign(socket, mfa_code: code, error: nil)}
  end

  def handle_event("mfa_submit", %{"mfa" => %{"code" => code}}, socket) do
    socket = assign(socket, loading: true, error: nil)

    case verify_mfa(socket.assigns.mfa_session_token, code) do
      {:ok, tokens} ->
        finish_login(socket, tokens)

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:mfa_code, "")
         |> assign(:error, message)}
    end
  end

  def handle_event("mfa_cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :credentials)
     |> assign(:mfa_session_token, nil)
     |> assign(:mfa_code, "")
     |> assign(:error, nil)
     |> assign(:loading, false)}
  end

  # In admin mode we intentionally omit the `role` query param so the session
  # endpoint derives the role from the Interactor profile's `metadata.role`
  # claim. Non-admin users who land on /admin/login simply get their default
  # role and are redirected to /dashboard.
  defp finish_login(socket, tokens) do
    redirect_url =
      if socket.assigns.admin_mode do
        "/auth/session?token=#{tokens["access_token"]}"
      else
        "/auth/session?token=#{tokens["access_token"]}&role=#{socket.assigns.role}"
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> redirect(to: redirect_url)}
  end

  defp authenticate(username, password) do
    url = "#{interactor_url()}/api/v1/users/login"

    body = %{
      org: org_name(),
      username: username,
      password: password
    }

    case Req.post(url, [json: body] ++ extra_req_opts()) do
      {:ok, %{status: 200, body: %{"mfa_required" => true, "session_token" => token}}} ->
        {:ok, :mfa_required, token}

      {:ok, %{status: 200, body: tokens}} ->
        {:ok, :tokens, tokens}

      {:ok, %{status: status, body: %{"error" => error}}} when status in [401, 403] ->
        {:error, friendly_auth_error(error)}

      {:ok, %{status: _, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status}} ->
        {:error, "Login failed (#{status})"}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Authentication service unavailable. Please try again later."}

      {:error, reason} ->
        Logger.error("Login failed: #{inspect(reason)}")
        {:error, "Connection error. Please try again."}
    end
  end

  defp verify_mfa(session_token, code) do
    url = "#{interactor_url()}/api/v1/users/login/mfa"
    body = %{session_token: session_token, code: code}

    case Req.post(url, [json: body] ++ extra_req_opts()) do
      {:ok, %{status: 200, body: tokens}} ->
        {:ok, tokens}

      {:ok, %{status: 401}} ->
        {:error, "Invalid code. Please try again."}

      {:ok, %{status: _, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status}} ->
        {:error, "Verification failed (#{status})"}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Authentication service unavailable. Please try again later."}

      {:error, reason} ->
        Logger.error("MFA verification failed: #{inspect(reason)}")
        {:error, "Connection error. Please try again."}
    end
  end

  defp friendly_auth_error("invalid_credentials"), do: "Wrong username or password."
  defp friendly_auth_error(other) when is_binary(other), do: other
  defp friendly_auth_error(_), do: "Sign-in failed. Please try again."

  defp normalize_role(role) when role in @roles, do: role
  defp normalize_role(_), do: nil

  defp redirect_path("parent"), do: "/parent"
  defp redirect_path("teacher"), do: "/teacher"
  defp redirect_path("admin"), do: "/admin"
  defp redirect_path(_), do: "/dashboard"

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "http://localhost:4001")

  defp org_name,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  # Allows tests to inject `plug: {Req.Test, FunSheepWeb.LoginLive}` without hitting the network.
  defp extra_req_opts, do: Application.get_env(:fun_sheep, :login_req_opts, [])

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] flex items-center justify-center p-4 sm:p-6">
      <div class="w-full max-w-md">
        <%!-- Logo / Header --%>
        <div class="text-center mb-6">
          <div class="inline-block">
            <span class="text-6xl">🐑</span>
          </div>
          <h1 class="text-3xl font-bold text-[#1C1C1E] mt-2">FunSheep</h1>
          <p class="text-[#8E8E93] font-medium text-sm mt-1">Learn. Play. Baa-come smarter!</p>
        </div>

        <%!-- Card --%>
        <div class="bg-white rounded-2xl shadow-md p-6 sm:p-8 border border-[#E5E5EA]">
          <h2 class="text-xl font-semibold text-[#1C1C1E] text-center mb-5">
            <span :if={@step == :credentials}>Welcome back!</span>
            <span :if={@step == :mfa}>Enter your code</span>
          </h2>

          <%!-- Google SSO (only visible on credentials step) --%>
          <a
            :if={@step == :credentials}
            href={~p"/auth/login/redirect?idp_hint=google"}
            class="w-full inline-flex items-center justify-center gap-2.5 px-6 py-3 rounded-full border border-[#E5E5EA] bg-white hover:bg-[#F5F5F7] text-[#1C1C1E] font-medium shadow-sm transition-colors mb-4"
            data-google-sso
          >
            <.google_icon />
            <span>Continue with Google</span>
          </a>

          <div :if={@step == :credentials} class="relative mb-4">
            <div class="absolute inset-0 flex items-center" aria-hidden="true">
              <div class="w-full border-t border-[#E5E5EA]"></div>
            </div>
            <div class="relative flex justify-center text-xs">
              <span class="bg-white px-2 text-[#8E8E93]">or with password</span>
            </div>
          </div>

          <%!-- Error --%>
          <div
            :if={@error}
            role="alert"
            class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm mb-4 flex items-center gap-2"
          >
            <span aria-hidden="true">⚠️</span> {@error}
          </div>

          <%!-- MFA step --%>
          <form
            :if={@step == :mfa}
            phx-change="mfa_validate"
            phx-submit="mfa_submit"
            class="space-y-4"
          >
            <p class="text-sm text-[#8E8E93] text-center">
              Open your authenticator app and enter the 6-digit code.
            </p>

            <div>
              <label for="mfa-code" class="sr-only">Authentication code</label>
              <input
                id="mfa-code"
                type="text"
                name="mfa[code]"
                value={@mfa_code}
                placeholder="123456"
                required
                autofocus
                inputmode="numeric"
                pattern="[0-9]*"
                autocomplete="one-time-code"
                maxlength="8"
                class="w-full text-center tracking-[0.5em] text-xl font-mono px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors text-[#1C1C1E]"
              />
            </div>

            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Verifying…", else: "Verify"}
            </button>

            <button
              type="button"
              phx-click="mfa_cancel"
              class="w-full text-sm text-[#8E8E93] hover:text-[#1C1C1E] font-medium"
            >
              Back to sign in
            </button>
          </form>

          <%!-- Credentials step --%>
          <form
            :if={@step == :credentials}
            phx-change="validate"
            phx-submit="login"
            class="space-y-4"
          >
            <%!-- Username --%>
            <div>
              <label
                for="login-username"
                class="block text-sm font-medium text-[#1C1C1E] mb-1.5"
              >
                Username or email
              </label>
              <input
                id="login-username"
                type="text"
                name="login[username]"
                value={@form["username"]}
                placeholder="Your username"
                required
                autofocus
                autocomplete="username"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors text-[#1C1C1E]"
              />
            </div>

            <%!-- Password --%>
            <div>
              <div class="flex items-baseline justify-between mb-1.5">
                <label for="login-password" class="block text-sm font-medium text-[#1C1C1E]">
                  Password
                </label>
                <.link
                  navigate={~p"/auth/forgot-password"}
                  class="text-xs font-medium text-[#4CD964] hover:text-[#3DBF55]"
                >
                  Forgot password?
                </.link>
              </div>
              <input
                id="login-password"
                type="password"
                name="login[password]"
                value={@form["password"]}
                placeholder="Shhh… it's a secret 🤫"
                required
                autocomplete="current-password"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors text-[#1C1C1E]"
              />
            </div>

            <%!-- Role Selector (below password per UX: login is primary, role is a context switch).
                 Hidden in admin mode — the admin role is derived server-side from the
                 Interactor profile's metadata.role claim. --%>
            <.role_selector :if={not @admin_mode} role={@role} />

            <%!-- Submit --%>
            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Signing in…", else: "Let's go! 🚀"}
            </button>
          </form>

          <div :if={not @admin_mode and @step == :credentials} class="mt-6 text-center">
            <p class="text-sm text-[#8E8E93]">
              New here?
              <.link
                navigate={~p"/auth/register?role=#{@role}"}
                class="text-[#4CD964] hover:text-[#3DBF55] font-semibold"
              >
                Create an account
              </.link>
            </p>
          </div>
        </div>

        <%!-- Flash --%>
        <div :if={@flash && @flash != %{}} class="mt-4">
          <div
            :if={Phoenix.Flash.get(@flash, :info)}
            class="bg-[#E8F8EB] border border-[#4CD964]/30 text-[#1C1C1E] px-4 py-3 rounded-xl text-sm"
          >
            {Phoenix.Flash.get(@flash, :info)}
          </div>
          <div
            :if={Phoenix.Flash.get(@flash, :error)}
            class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm"
          >
            {Phoenix.Flash.get(@flash, :error)}
          </div>
        </div>

        <p class="text-center text-xs text-[#8E8E93] mt-6">
          Secured by Interactor 🔐
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the role selector. Student is a large hero card (selected by
  default); Teacher and Parent are small pill chips shown as secondary options.
  """
  attr :role, :string, required: true

  def role_selector(assigns) do
    ~H"""
    <div role="radiogroup" aria-label="I am signing in as">
      <p class="text-xs font-medium uppercase tracking-wide text-[#8E8E93] mb-2">
        Sign in as
      </p>

      <%!-- Student hero card --%>
      <button
        type="button"
        role="radio"
        aria-checked={@role == "student"}
        phx-click="select_role"
        phx-value-role="student"
        class={[
          "w-full flex items-center gap-4 p-4 rounded-2xl border-2 transition-colors text-left",
          if(@role == "student",
            do: "border-[#4CD964] bg-[#E8F8EB]",
            else: "border-[#E5E5EA] bg-white hover:border-[#4CD964]/40"
          )
        ]}
      >
        <div class="flex items-center justify-center w-12 h-12 rounded-2xl bg-white shadow-sm text-3xl">
          🎒
        </div>
        <div class="flex-1">
          <div class="text-base font-semibold text-[#1C1C1E]">Student</div>
          <div class="text-xs text-[#8E8E93]">The full learning experience</div>
        </div>
        <div
          :if={@role == "student"}
          aria-hidden="true"
          class="w-6 h-6 rounded-full bg-[#4CD964] flex items-center justify-center text-white text-sm"
        >
          ✓
        </div>
      </button>

      <%!-- Teacher / Parent small chips --%>
      <div class="mt-2 flex items-center justify-center gap-2">
        <span class="text-xs text-[#8E8E93]">or</span>
        <.role_chip role={@role} value="teacher" label="Teacher" emoji="🎓" />
        <.role_chip role={@role} value="parent" label="Parent" emoji="👨‍👩‍👧" />
      </div>
    </div>
    """
  end

  defp google_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class="w-5 h-5" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.76h3.56c2.08-1.92 3.28-4.74 3.28-8.09z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.56-2.76c-.98.66-2.23 1.06-3.72 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A10.99 10.99 0 0 0 12 23z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.11A6.6 6.6 0 0 1 5.5 12c0-.73.13-1.44.34-2.11V7.05H2.18A10.99 10.99 0 0 0 1 12c0 1.78.43 3.47 1.18 4.95l3.66-2.84z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.2 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.05l3.66 2.84C6.71 7.31 9.14 5.38 12 5.38z"
      />
    </svg>
    """
  end

  attr :role, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :emoji, :string, required: true

  defp role_chip(assigns) do
    ~H"""
    <button
      type="button"
      role="radio"
      aria-checked={@role == @value}
      phx-click="select_role"
      phx-value-role={@value}
      class={[
        "inline-flex items-center gap-1.5 px-4 py-2.5 min-h-[44px] rounded-full border text-sm font-medium transition-colors",
        if(@role == @value,
          do: "border-[#4CD964] bg-[#E8F8EB] text-[#1C1C1E]",
          else: "border-[#E5E5EA] bg-white text-[#8E8E93] hover:border-[#4CD964]/40"
        )
      ]}
    >
      <span aria-hidden="true">{@emoji}</span>
      <span>{@label}</span>
    </button>
    """
  end
end
