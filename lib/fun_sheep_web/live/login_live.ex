defmodule FunSheepWeb.LoginLive do
  use FunSheepWeb, :live_view

  require Logger

  @impl true
  def mount(_params, session, socket) do
    if session["current_user"] || session["dev_user"] do
      user = session["current_user"] || session["dev_user"]
      role = user["role"] || "student"
      {:ok, redirect(socket, to: redirect_path(role))}
    else
      {:ok,
       socket
       |> assign(:page_title, "Login")
       |> assign(:form, %{"username" => "", "password" => ""})
       |> assign(:error, nil)
       |> assign(:loading, false), layout: false}
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
      {:ok, _user, tokens} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> redirect(to: "/auth/session?token=#{tokens["access_token"]}")}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, message)}
    end
  end

  defp authenticate(username, password) do
    url = "#{interactor_url()}/api/v1/users/login"

    body = %{
      org: org_name(),
      username: username,
      password: password
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: tokens}} ->
        user = extract_user(tokens)
        {:ok, user, tokens}

      {:ok, %{status: 401, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: 403, body: %{"error" => error}}} ->
        {:error, error}

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

  defp extract_user(tokens) do
    case decode_jwt(tokens["access_token"]) do
      {:ok, claims} ->
        %{
          "id" => claims["sub"],
          "interactor_user_id" => claims["sub"],
          "email" => claims["email"] || claims["username"],
          "display_name" => claims["name"] || claims["username"] || "User",
          "role" => get_in(claims, ["metadata", "role"]) || "student",
          "org" => claims["org"],
          "username" => claims["username"]
        }

      {:error, _} ->
        %{
          "id" => "unknown",
          "interactor_user_id" => "unknown",
          "email" => "",
          "display_name" => "User",
          "role" => "student"
        }
    end
  end

  defp decode_jwt(token) when is_binary(token) do
    case String.split(token, ".") do
      [_, payload, _] ->
        case Base.url_decode64(payload, padding: false) do
          {:ok, json} -> Jason.decode(json)
          :error -> {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_jwt}
    end
  end

  defp decode_jwt(_), do: {:error, :no_token}

  defp redirect_path("parent"), do: "/parent"
  defp redirect_path("teacher"), do: "/teacher"
  defp redirect_path("admin"), do: "/admin"
  defp redirect_path(_), do: "/dashboard"

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "http://localhost:4001")

  defp org_name,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-white to-indigo-50 flex items-center justify-center p-6">
      <div class="w-full max-w-md animate-slide-up">
        <%!-- Logo / Header --%>
        <div class="text-center mb-8">
          <div class="inline-block animate-float">
            <span class="text-7xl">🐑</span>
          </div>
          <h1 class="text-3xl font-extrabold text-gray-900 mt-3">Fun Sheep</h1>
          <p class="text-purple-500 font-medium mt-1">Learn. Play. Baa-come smarter!</p>
        </div>

        <%!-- Login Card --%>
        <div class="bg-white rounded-2xl shadow-lg p-8 border border-purple-100">
          <h2 class="text-xl font-bold text-gray-900 text-center mb-6">Welcome back! 👋</h2>

          <%!-- Error --%>
          <div
            :if={@error}
            class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded-xl text-sm mb-4 flex items-center gap-2"
          >
            <span>😬</span> {@error}
          </div>

          <form phx-change="validate" phx-submit="login" class="space-y-4">
            <%!-- Username --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Username</label>
              <input
                type="text"
                name="login[username]"
                value={@form["username"]}
                placeholder="Your username"
                required
                autofocus
                class="w-full px-4 py-3 bg-purple-50/50 border border-purple-100 focus:border-purple-400 focus:bg-white rounded-full outline-none transition-all text-gray-900"
              />
            </div>

            <%!-- Password --%>
            <div>
              <label class="block text-sm font-semibold text-gray-700 mb-1">Password</label>
              <input
                type="password"
                name="login[password]"
                value={@form["password"]}
                placeholder="Shhh... it's a secret 🤫"
                required
                class="w-full px-4 py-3 bg-purple-50/50 border border-purple-100 focus:border-purple-400 focus:bg-white rounded-full outline-none transition-all text-gray-900"
              />
            </div>

            <%!-- Submit --%>
            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-700 hover:to-indigo-700 text-white font-bold px-6 py-3 rounded-full shadow-lg shadow-purple-200 transition-all disabled:opacity-50 disabled:cursor-not-allowed btn-bounce"
            >
              {if @loading, do: "Logging in... ⏳", else: "Let's Go! 🚀"}
            </button>
          </form>

          <div class="mt-6 text-center">
            <p class="text-sm text-gray-500">
              New here?
              <a href="/register" class="text-purple-600 hover:text-purple-700 font-bold">
                Create an account ✨
              </a>
            </p>
          </div>
        </div>

        <%!-- Flash Messages --%>
        <div :if={@flash != %{}} class="mt-4">
          <div
            :if={Phoenix.Flash.get(@flash, :info)}
            class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-xl text-sm"
          >
            {Phoenix.Flash.get(@flash, :info)}
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
