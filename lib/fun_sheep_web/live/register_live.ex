defmodule FunSheepWeb.RegisterLive do
  use FunSheepWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    if session["current_user"] || session["dev_user"] do
      {:ok, redirect(socket, to: "/dashboard")}
    else
      changeset = %{
        "email" => "",
        "username" => "",
        "password" => "",
        "password_confirmation" => "",
        "role" => "student"
      }

      {:ok,
       socket
       |> assign(:page_title, "Register")
       |> assign(:form, changeset)
       |> assign(:errors, %{})
       |> assign(:success, false)
       |> assign(:loading, false), layout: false}
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
      {:noreply, assign(socket, errors: errors)}
    else
      socket = assign(socket, loading: true)

      case register_user(params) do
        {:ok, message} ->
          {:noreply,
           socket
           |> assign(:success, true)
           |> assign(:loading, false)
           |> assign(:success_message, message)}

        {:error, error_msg} ->
          {:noreply,
           socket
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

  defp register_user(params) do
    url = "#{interactor_url()}/api/v1/orgs/#{org_name()}/users/register"

    body = %{
      email: params["email"],
      username: params["username"],
      password: params["password"],
      metadata: %{role: params["role"] || "student"},
      redirect_uri: FunSheepWeb.Endpoint.url() <> "/auth/verify-email"
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, resp["message"] || "Registration successful! Please check your email."}

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
        {:error, "Registration failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp org_name,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-50 via-white to-purple-50 flex items-center justify-center p-6">
      <div class="w-full max-w-md animate-slide-up">
        <%!-- Logo / Header --%>
        <div class="text-center mb-8">
          <div class="inline-block animate-float">
            <span class="text-7xl">🐑</span>
          </div>
          <h1 class="text-3xl font-extrabold text-gray-900 mt-3">Join the Flock!</h1>
          <p class="text-purple-500 font-medium mt-1">Start your Fun Sheep adventure</p>
        </div>

        <%!-- Success State --%>
        <div :if={@success} class="bg-white rounded-2xl shadow-lg p-8 text-center border border-emerald-200 animate-slide-up">
          <div class="animate-confetti">
            <span class="text-6xl">🎉</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 mt-4 mb-2">Check your email!</h2>
          <p class="text-gray-500 mb-6">{@success_message}</p>
          <a
            href="/"
            class="inline-flex items-center justify-center bg-gradient-to-r from-purple-600 to-indigo-600 text-white font-bold px-6 py-3 rounded-full shadow-lg shadow-purple-200 transition-all btn-bounce"
          >
            Go to Login 🚀
          </a>
        </div>

        <%!-- Registration Form --%>
        <div :if={!@success} class="bg-white rounded-2xl shadow-lg p-8 border border-purple-100">
          <h2 class="text-xl font-bold text-gray-900 text-center mb-6">Create your account ✨</h2>

          <%!-- Base error --%>
          <div
            :if={@errors["base"]}
            class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded-xl text-sm mb-4 flex items-center gap-2"
          >
            <span>😬</span> {@errors["base"]}
          </div>

          <form phx-change="validate" phx-submit="register" class="space-y-4">
            <%!-- Role Selection --%>
            <div>
              <label class="block text-sm font-bold text-gray-700 mb-2">I am a...</label>
              <div class="grid grid-cols-3 gap-2">
                <label
                  :for={{role, emoji} <- [{"student", "🎒"}, {"parent", "👨‍👩‍👧"}, {"teacher", "🎓"}]}
                  class={[
                    "flex flex-col items-center justify-center px-3 py-3 rounded-xl border-2 text-sm font-bold cursor-pointer transition-all",
                    if(@form["role"] == role,
                      do: "bg-purple-600 border-purple-600 text-white shadow-md shadow-purple-200",
                      else: "bg-white border-purple-100 text-gray-700 hover:border-purple-300"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    name="registration[role]"
                    value={role}
                    checked={@form["role"] == role}
                    class="sr-only"
                  />
                  <span class="text-xl mb-1">{emoji}</span>
                  {String.capitalize(role)}
                </label>
              </div>
            </div>

            <%!-- Email --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Email</label>
              <input
                type="email"
                name="registration[email]"
                value={@form["email"]}
                placeholder="you@school.edu"
                required
                class={[
                  "w-full px-4 py-3 bg-purple-50/50 border rounded-full outline-none transition-all text-gray-900",
                  if(@errors["email"],
                    do: "border-red-300 bg-red-50/50",
                    else: "border-purple-100 focus:border-purple-400 focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["email"]} class="text-red-500 text-xs mt-1 font-medium">
                {@errors["email"]}
              </p>
            </div>

            <%!-- Username --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Username</label>
              <input
                type="text"
                name="registration[username]"
                value={@form["username"]}
                placeholder="Pick something cool"
                required
                class={[
                  "w-full px-4 py-3 bg-purple-50/50 border rounded-full outline-none transition-all text-gray-900",
                  if(@errors["username"],
                    do: "border-red-300 bg-red-50/50",
                    else: "border-purple-100 focus:border-purple-400 focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["username"]} class="text-red-500 text-xs mt-1 font-medium">
                {@errors["username"]}
              </p>
            </div>

            <%!-- Password --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Password</label>
              <input
                type="password"
                name="registration[password]"
                value={@form["password"]}
                placeholder="Make it strong 💪 (min 8 chars)"
                required
                class={[
                  "w-full px-4 py-3 bg-purple-50/50 border rounded-full outline-none transition-all text-gray-900",
                  if(@errors["password"],
                    do: "border-red-300 bg-red-50/50",
                    else: "border-purple-100 focus:border-purple-400 focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["password"]} class="text-red-500 text-xs mt-1 font-medium">
                {@errors["password"]}
              </p>
            </div>

            <%!-- Confirm Password --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Confirm Password</label>
              <input
                type="password"
                name="registration[password_confirmation]"
                value={@form["password_confirmation"]}
                placeholder="One more time!"
                required
                class={[
                  "w-full px-4 py-3 bg-purple-50/50 border rounded-full outline-none transition-all text-gray-900",
                  if(@errors["password_confirmation"],
                    do: "border-red-300 bg-red-50/50",
                    else: "border-purple-100 focus:border-purple-400 focus:bg-white"
                  )
                ]}
              />
              <p :if={@errors["password_confirmation"]} class="text-red-500 text-xs mt-1 font-medium">
                {@errors["password_confirmation"]}
              </p>
            </div>

            <%!-- Submit --%>
            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-700 hover:to-indigo-700 text-white font-bold px-6 py-3 rounded-full shadow-lg shadow-purple-200 transition-all disabled:opacity-50 disabled:cursor-not-allowed btn-bounce"
            >
              {if @loading, do: "Creating... ⏳", else: "Let's Get Started! 🎉"}
            </button>
          </form>

          <div class="mt-6 text-center">
            <p class="text-sm text-gray-500">
              Already have an account?
              <a href="/" class="text-purple-600 hover:text-purple-700 font-bold">
                Sign in
              </a>
            </p>
          </div>
        </div>

        <p class="text-center text-xs text-gray-400 mt-8">
          Powered by Interactor 🔐
        </p>
      </div>
    </div>
    """
  end
end
