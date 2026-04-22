defmodule FunSheepWeb.ClaimCodeLive do
  @moduledoc """
  Claim-code redemption for Flow B (§5.2). Route: `/claim/:code`.

  A student who was handed an invite code by their parent lands here,
  authenticates via the existing auth flow (or is already signed in),
  and redeems the code — which creates an `:active` `student_guardian`
  link between them and the parent.

  If the visitor is not yet signed in, we show the code + a sign-in
  link and preserve the code across the login round trip via the URL
  path.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Accounts
  alias FunSheep.InviteCodes

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    user = socket.assigns[:current_user]
    code = code |> String.upcase() |> String.trim()
    invite = InviteCodes.get_by_code(code)

    socket =
      socket
      |> assign(
        page_title: "Accept invite",
        code: code,
        invite: invite,
        current_user: user,
        redeem_result: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("redeem", _params, socket) do
    student =
      case socket.assigns.current_user do
        %{"id" => id} when is_binary(id) -> Accounts.get_user_role(id)
        _ -> nil
      end

    cond do
      is_nil(student) ->
        {:noreply, assign(socket, :redeem_result, {:error, :not_signed_in})}

      student.role != :student ->
        {:noreply, assign(socket, :redeem_result, {:error, :not_a_student})}

      true ->
        result = InviteCodes.redeem(socket.assigns.code, student)
        {:noreply, assign(socket, :redeem_result, result)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto px-4 py-8 space-y-6">
      <%= cond do %>
        <% is_nil(@invite) -> %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center">
            <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white mb-2">
              Code not found
            </h1>
            <p class="text-sm text-[#8E8E93]">
              "{@code}" doesn't match any active invite. Double-check the code
              and try again.
            </p>
          </div>
        <% not FunSheep.Accounts.InviteCode.active?(@invite) -> %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center">
            <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white mb-2">
              This invite has already been used or expired
            </h1>
            <p class="text-sm text-[#8E8E93]">
              Ask the person who gave it to you to generate a new one.
            </p>
          </div>
        <% match?({:ok, _}, @redeem_result) -> %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
            <div class="text-5xl" aria-hidden="true">💚</div>
            <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white">
              You're all set
            </h1>
            <p class="text-sm text-[#1C1C1E] dark:text-white">
              You're now linked with your grown-up. They can see your practice
              progress and help you unlock more when you need it.
            </p>
            <.link
              navigate="/dashboard"
              class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
            >
              Go to your dashboard
            </.link>
          </div>
        <% true -> %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
            <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white">
              Accept invite from {@invite.child_display_name
              |> then(fn _ -> "your grown-up" end)}
            </h1>
            <p class="text-sm text-[#8E8E93]">
              You've been invited to link your FunSheep account.
            </p>

            <div
              :if={match?({:error, :not_signed_in}, @redeem_result)}
              class="bg-[#FFF9E8] rounded-xl p-3 text-sm"
            >
              You need to sign in first.
              <.link navigate="/auth/login" class="text-[#007AFF] hover:underline font-medium">
                Sign in →
              </.link>
            </div>
            <div
              :if={match?({:error, :not_a_student}, @redeem_result)}
              class="bg-[#FFF9E8] rounded-xl p-3 text-sm"
            >
              Only student accounts can accept this kind of invite.
            </div>

            <button
              type="button"
              phx-click="redeem"
              class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
            >
              Accept invite
            </button>
          </div>
      <% end %>
    </div>
    """
  end
end
