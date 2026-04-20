defmodule FunSheepWeb.RegisterLive do
  @moduledoc """
  Custom registration screen.

  Mirrors `LoginLive`'s role selector: Student is featured as the large hero
  card, Teacher and Parent are secondary chips. The selected role is submitted
  to Interactor as `metadata.role` so downstream login flows can resolve the
  corresponding local `UserRole`.
  """

  use FunSheepWeb, :live_view

  require Logger

  @roles ~w(student teacher parent)
  @default_role "student"

  @impl true
  def mount(params, session, socket) do
    if session["current_user"] || session["dev_user"] do
      {:ok, redirect(socket, to: "/dashboard")}
    else
      initial_role = normalize_role(params["role"]) || @default_role

      form = %{
        "email" => "",
        "username" => "",
        "password" => "",
        "password_confirmation" => ""
      }

      {:ok,
       socket
       |> assign(:page_title, "Create an account")
       |> assign(:role, initial_role)
       |> assign(:form, form)
       |> assign(:errors, %{})
       |> assign(:success, false)
       |> assign(:success_message, nil)
       |> assign(:loading, false), layout: false}
    end
  end

  @impl true
  def handle_event("select_role", %{"role" => role}, socket) do
    case normalize_role(role) do
      nil -> {:noreply, socket}
      r -> {:noreply, assign(socket, role: r)}
    end
  end

  @impl true
  def handle_event("validate", %{"registration" => params}, socket) do
    errors = validate_params(params)
    {:noreply, assign(socket, form: params, errors: errors)}
  end

  @impl true
  def handle_event("register", %{"registration" => params}, socket) do
    errors = validate_params(params)

    if map_size(errors) > 0 do
      {:noreply, assign(socket, form: params, errors: errors)}
    else
      socket = assign(socket, loading: true, errors: %{})

      case register_user(params, socket.assigns.role) do
        {:ok, message} ->
          {:noreply,
           socket
           |> assign(:success, true)
           |> assign(:loading, false)
           |> assign(:success_message, message)}

        {:error, error_msg} ->
          {:noreply,
           socket
           |> assign(:form, params)
           |> assign(:loading, false)
           |> assign(:errors, %{"base" => error_msg})}
      end
    end
  end

  defp validate_params(params) do
    errors = %{}

    errors =
      if String.trim(params["email"] || "") == "",
        do: Map.put(errors, "email", "Email is required"),
        else: errors

    errors =
      if String.trim(params["username"] || "") == "",
        do: Map.put(errors, "username", "Username is required"),
        else: errors

    errors =
      if String.length(params["password"] || "") < 8,
        do: Map.put(errors, "password", "Password must be at least 8 characters"),
        else: errors

    errors =
      if params["password"] != params["password_confirmation"],
        do: Map.put(errors, "password_confirmation", "Passwords don't match"),
        else: errors

    errors
  end

  defp register_user(params, role) do
    url = "#{interactor_url()}/api/v1/orgs/#{org_name()}/users/register"

    body = %{
      email: params["email"],
      username: params["username"],
      password: params["password"],
      metadata: %{role: role},
      redirect_uri: FunSheepWeb.Endpoint.url() <> "/auth/login"
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok,
         resp["message"] ||
           "Registration successful! Check your email to verify your account."}

      {:ok, %{status: 422, body: %{"errors" => errors}}} ->
        msg =
          errors
          |> Enum.map(fn {field, messages} ->
            "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
          end)
          |> Enum.join(". ")

        {:error, msg}

      {:ok, %{status: _, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Registration failed (#{status}): #{inspect(body)}")
        {:error, "Registration failed (#{status}). Please try again."}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Registration service unavailable. Please try again later."}

      {:error, reason} ->
        Logger.error("Registration error: #{inspect(reason)}")
        {:error, "Connection error. Please try again."}
    end
  end

  defp normalize_role(role) when role in @roles, do: role
  defp normalize_role(_), do: nil

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp org_name,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] flex items-center justify-center p-4 sm:p-6">
      <div class="w-full max-w-md">
        <%!-- Logo --%>
        <div class="text-center mb-6">
          <div class="inline-block">
            <span class="text-6xl">🐑</span>
          </div>
          <h1 class="text-3xl font-bold text-[#1C1C1E] mt-2">Join the Flock!</h1>
          <p class="text-[#8E8E93] font-medium text-sm mt-1">Start your FunSheep adventure</p>
        </div>

        <%!-- Success State --%>
        <div
          :if={@success}
          class="bg-white rounded-2xl shadow-md p-8 text-center border border-[#E5E5EA]"
        >
          <div>
            <span class="text-6xl">🎉</span>
          </div>
          <h2 class="text-xl font-semibold text-[#1C1C1E] mt-4 mb-2">Check your email!</h2>
          <p class="text-[#8E8E93] mb-6 text-sm">{@success_message}</p>
          <.link
            navigate={~p"/auth/login?role=#{@role}"}
            class="inline-flex items-center justify-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2.5 rounded-full shadow-md transition-colors"
          >
            Go to sign in
          </.link>
        </div>

        <%!-- Registration Form --%>
        <div :if={!@success} class="bg-white rounded-2xl shadow-md p-6 sm:p-8 border border-[#E5E5EA]">
          <h2 class="text-xl font-semibold text-[#1C1C1E] text-center mb-5">Create your account</h2>

          <.role_selector role={@role} />

          <%!-- Google SSO --%>
          <a
            href={~p"/auth/login/redirect?idp_hint=google"}
            class="w-full inline-flex items-center justify-center gap-2.5 px-6 py-3 rounded-full border border-[#E5E5EA] bg-white hover:bg-[#F5F5F7] text-[#1C1C1E] font-medium shadow-sm transition-colors mb-4"
            data-google-sso
          >
            <.google_icon />
            <span>Continue with Google</span>
          </a>

          <div class="relative mb-4">
            <div class="absolute inset-0 flex items-center" aria-hidden="true">
              <div class="w-full border-t border-[#E5E5EA]"></div>
            </div>
            <div class="relative flex justify-center text-xs">
              <span class="bg-white px-2 text-[#8E8E93]">or with email</span>
            </div>
          </div>

          <div
            :if={@errors["base"]}
            role="alert"
            class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm mb-4 flex items-center gap-2"
          >
            <span aria-hidden="true">⚠️</span> {@errors["base"]}
          </div>

          <form phx-change="validate" phx-submit="register" class="space-y-4">
            <%!-- Email --%>
            <div>
              <label for="reg-email" class="block text-sm font-medium text-[#1C1C1E] mb-1.5">
                Email
              </label>
              <input
                id="reg-email"
                type="email"
                name="registration[email]"
                value={@form["email"]}
                placeholder="you@school.edu"
                required
                autocomplete="email"
                class={[
                  "w-full px-4 py-3 bg-[#F5F5F7] border rounded-full outline-none transition-colors text-[#1C1C1E]",
                  if(@errors["email"],
                    do: "border-[#FF3B30]/40",
                    else: "border-transparent focus:border-[#4CD964] focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["email"]} class="text-[#FF3B30] text-xs mt-1 font-medium">
                {@errors["email"]}
              </p>
            </div>

            <%!-- Username --%>
            <div>
              <label for="reg-username" class="block text-sm font-medium text-[#1C1C1E] mb-1.5">
                Username
              </label>
              <input
                id="reg-username"
                type="text"
                name="registration[username]"
                value={@form["username"]}
                placeholder="Pick something cool"
                required
                autocomplete="username"
                class={[
                  "w-full px-4 py-3 bg-[#F5F5F7] border rounded-full outline-none transition-colors text-[#1C1C1E]",
                  if(@errors["username"],
                    do: "border-[#FF3B30]/40",
                    else: "border-transparent focus:border-[#4CD964] focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["username"]} class="text-[#FF3B30] text-xs mt-1 font-medium">
                {@errors["username"]}
              </p>
            </div>

            <%!-- Password --%>
            <div>
              <label for="reg-password" class="block text-sm font-medium text-[#1C1C1E] mb-1.5">
                Password
              </label>
              <input
                id="reg-password"
                type="password"
                name="registration[password]"
                value={@form["password"]}
                placeholder="At least 8 characters"
                required
                autocomplete="new-password"
                class={[
                  "w-full px-4 py-3 bg-[#F5F5F7] border rounded-full outline-none transition-colors text-[#1C1C1E]",
                  if(@errors["password"],
                    do: "border-[#FF3B30]/40",
                    else: "border-transparent focus:border-[#4CD964] focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["password"]} class="text-[#FF3B30] text-xs mt-1 font-medium">
                {@errors["password"]}
              </p>
            </div>

            <%!-- Confirm Password --%>
            <div>
              <label
                for="reg-password-confirm"
                class="block text-sm font-medium text-[#1C1C1E] mb-1.5"
              >
                Confirm password
              </label>
              <input
                id="reg-password-confirm"
                type="password"
                name="registration[password_confirmation]"
                value={@form["password_confirmation"]}
                placeholder="One more time"
                required
                autocomplete="new-password"
                class={[
                  "w-full px-4 py-3 bg-[#F5F5F7] border rounded-full outline-none transition-colors text-[#1C1C1E]",
                  if(@errors["password_confirmation"],
                    do: "border-[#FF3B30]/40",
                    else: "border-transparent focus:border-[#4CD964] focus:bg-white"
                  )
                ]}
              />
              <p
                :if={@errors["password_confirmation"]}
                class="text-[#FF3B30] text-xs mt-1 font-medium"
              >
                {@errors["password_confirmation"]}
              </p>
            </div>

            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Creating…", else: "Create account 🎉"}
            </button>
          </form>

          <div class="mt-6 text-center">
            <p class="text-sm text-[#8E8E93]">
              Already have an account?
              <.link
                navigate={~p"/auth/login?role=#{@role}"}
                class="text-[#4CD964] hover:text-[#3DBF55] font-semibold"
              >
                Sign in
              </.link>
            </p>
          </div>
        </div>

        <p class="text-center text-xs text-[#8E8E93] mt-6">
          Secured by Interactor 🔐
        </p>
      </div>
    </div>
    """
  end

  attr :role, :string, required: true

  defp role_selector(assigns) do
    ~H"""
    <div class="mb-5" role="radiogroup" aria-label="I'm registering as">
      <p class="text-xs font-medium uppercase tracking-wide text-[#8E8E93] mb-2">
        I'm registering as
      </p>

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
