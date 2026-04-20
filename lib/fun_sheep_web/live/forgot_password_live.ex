defmodule FunSheepWeb.ForgotPasswordLive do
  @moduledoc """
  Password recovery request screen.

  Posts the provided email to Interactor's
  `/api/v1/orgs/:org_name/users/password/reset-request` endpoint. The endpoint
  responds the same whether or not the email exists (to prevent enumeration),
  so the UI always shows a neutral "check your email" confirmation on success.
  """

  use FunSheepWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset your password")
     |> assign(:form, %{"email" => ""})
     |> assign(:error, nil)
     |> assign(:submitted, false)
     |> assign(:loading, false), layout: false}
  end

  @impl true
  def handle_event("validate", %{"forgot" => params}, socket) do
    {:noreply, assign(socket, form: params, error: nil)}
  end

  @impl true
  def handle_event("submit", %{"forgot" => %{"email" => email} = params}, socket) do
    cond do
      String.trim(email) == "" ->
        {:noreply,
         socket
         |> assign(:form, params)
         |> assign(:error, "Please enter your email address.")}

      true ->
        socket = assign(socket, loading: true, error: nil)

        case request_reset(email) do
          :ok ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:submitted, true)}

          {:error, message} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:error, message)}
        end
    end
  end

  defp request_reset(email) do
    url =
      "#{interactor_url()}/api/v1/orgs/#{org_name()}/users/password/reset-request"

    body = %{
      email: email,
      redirect_uri: FunSheepWeb.Endpoint.url() <> "/auth/reset-password"
    }

    case Req.post(url, json: body) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: _, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status}} ->
        Logger.warning("Password reset-request returned #{status}")
        {:error, "We couldn't start password reset. Please try again."}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, "Password reset service unavailable. Please try again later."}

      {:error, reason} ->
        Logger.error("Password reset-request error: #{inspect(reason)}")
        {:error, "Connection error. Please try again."}
    end
  end

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
          <h1 class="text-3xl font-bold text-[#1C1C1E] mt-2">Reset your password</h1>
          <p class="text-[#8E8E93] font-medium text-sm mt-1">
            We'll send you a link to reset it.
          </p>
        </div>

        <div class="bg-white rounded-2xl shadow-md p-6 sm:p-8 border border-[#E5E5EA]">
          <div :if={@submitted}>
            <div class="text-center">
              <span class="text-5xl">📬</span>
              <h2 class="text-lg font-semibold text-[#1C1C1E] mt-3">Check your email</h2>
              <p class="text-sm text-[#8E8E93] mt-2">
                If an account exists for <strong>{@form["email"]}</strong>, a password reset link is on its way. It may take a few minutes to arrive.
              </p>
              <.link
                navigate={~p"/auth/login"}
                class="inline-flex mt-6 items-center justify-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2.5 rounded-full shadow-md transition-colors"
              >
                Back to sign in
              </.link>
            </div>
          </div>

          <form :if={!@submitted} phx-change="validate" phx-submit="submit" class="space-y-4">
            <div
              :if={@error}
              role="alert"
              class="bg-[#FFE5E3] border border-[#FF3B30]/20 text-[#FF3B30] px-4 py-3 rounded-xl text-sm flex items-center gap-2"
            >
              <span aria-hidden="true">⚠️</span> {@error}
            </div>

            <div>
              <label for="forgot-email" class="block text-sm font-medium text-[#1C1C1E] mb-1.5">
                Email
              </label>
              <input
                id="forgot-email"
                type="email"
                name="forgot[email]"
                value={@form["email"]}
                placeholder="you@school.edu"
                required
                autofocus
                autocomplete="email"
                class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors text-[#1C1C1E]"
              />
            </div>

            <button
              type="submit"
              disabled={@loading}
              class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {if @loading, do: "Sending…", else: "Send reset link"}
            </button>

            <div class="text-center">
              <.link
                navigate={~p"/auth/login"}
                class="text-sm text-[#8E8E93] hover:text-[#1C1C1E]"
              >
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
