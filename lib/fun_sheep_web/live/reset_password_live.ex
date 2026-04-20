defmodule FunSheepWeb.ResetPasswordLive do
  @moduledoc """
  Accepts a reset token in the URL and lets the user set a new password.

  Submits to Interactor's
  `/api/v1/orgs/:org_name/users/password/reset` with the token and new
  password. On success, redirects to sign-in.
  """

  use FunSheepWeb, :live_view

  require Logger

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Set a new password")
     |> assign(:token, token)
     |> assign(:form, %{"password" => "", "password_confirmation" => ""})
     |> assign(:errors, %{})
     |> assign(:success, false)
     |> assign(:loading, false), layout: false}
  end

  @impl true
  def handle_event("validate", %{"reset" => params}, socket) do
    {:noreply, assign(socket, form: params, errors: validate(params))}
  end

  @impl true
  def handle_event("submit", %{"reset" => params}, socket) do
    errors = validate(params)

    if map_size(errors) > 0 do
      {:noreply, assign(socket, form: params, errors: errors)}
    else
      socket = assign(socket, loading: true, errors: %{})

      case reset(socket.assigns.token, params["password"]) do
        :ok ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:success, true)}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:form, params)
           |> assign(:loading, false)
           |> assign(:errors, %{"base" => message})}
      end
    end
  end

  defp validate(params) do
    errors = %{}

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

  defp reset(token, password) do
    url =
      "#{interactor_url()}/api/v1/orgs/#{org_name()}/users/password/reset"

    body = %{token: token, password: password}

    case Req.post(url, json: body) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 400, body: %{"error" => error}}} ->
        {:error, friendly_error(error)}

      {:ok, %{status: _, body: %{"error" => error}}} ->
        {:error, friendly_error(error)}

      {:ok, %{status: status}} ->
        Logger.warning("Password reset returned #{status}")
        {:error, "We couldn't reset your password. The link may have expired."}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Password reset service unavailable. Please try again later."}

      {:error, reason} ->
        Logger.error("Password reset error: #{inspect(reason)}")
        {:error, "Connection error. Please try again."}
    end
  end

  defp friendly_error("invalid_or_expired_token"),
    do: "This reset link is invalid or has expired. Please request a new one."

  defp friendly_error(other) when is_binary(other), do: other
  defp friendly_error(_), do: "Password reset failed. Please try again."

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp org_name,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] flex items-center justify-center p-4 sm:p-6">
      <div class="w-full max-w-md">
        <div class="text-center mb-6">
          <div class="inline-block">
            <span class="text-6xl">🐑</span>
          </div>
          <h1 class="text-3xl font-bold text-[#1C1C1E] mt-2">Set a new password</h1>
          <p class="text-[#8E8E93] font-medium text-sm mt-1">
            Choose something you'll remember.
          </p>
        </div>

        <div class="bg-white rounded-2xl shadow-md p-6 sm:p-8 border border-[#E5E5EA]">
          <div :if={@success} class="text-center">
            <span class="text-5xl">✅</span>
            <h2 class="text-lg font-semibold text-[#1C1C1E] mt-3">Password updated</h2>
            <p class="text-sm text-[#8E8E93] mt-2">
              Your password has been reset. You can sign in now.
            </p>
            <.link
              navigate={~p"/auth/login"}
              class="inline-flex mt-6 items-center justify-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2.5 rounded-full shadow-md transition-colors"
            >
              Go to sign in
            </.link>
          </div>

          <form :if={!@success} phx-change="validate" phx-submit="submit" class="space-y-4">
            <div
              :if={@errors["base"]}
              role="alert"
              class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm flex items-center gap-2"
            >
              <span aria-hidden="true">⚠️</span> {@errors["base"]}
            </div>

            <div>
              <label for="reset-password" class="block text-sm font-medium text-[#1C1C1E] mb-1.5">
                New password
              </label>
              <input
                id="reset-password"
                type="password"
                name="reset[password]"
                value={@form["password"]}
                placeholder="At least 8 characters"
                required
                autofocus
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

            <div>
              <label
                for="reset-password-confirm"
                class="block text-sm font-medium text-[#1C1C1E] mb-1.5"
              >
                Confirm password
              </label>
              <input
                id="reset-password-confirm"
                type="password"
                name="reset[password_confirmation]"
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
              {if @loading, do: "Updating…", else: "Update password"}
            </button>

            <div class="text-center">
              <.link navigate={~p"/auth/login"} class="text-sm text-[#8E8E93] hover:text-[#1C1C1E]">
                ← Back to sign in
              </.link>
            </div>
          </form>
        </div>

        <p class="text-center text-xs text-[#8E8E93] mt-6">
          Secured by Interactor 🔐
        </p>
      </div>
    </div>
    """
  end
end
