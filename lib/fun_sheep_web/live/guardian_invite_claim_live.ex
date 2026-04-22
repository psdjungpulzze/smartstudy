defmodule FunSheepWeb.GuardianInviteClaimLive do
  @moduledoc """
  Claim endpoint for email-only student→guardian invites.
  Route: `/guardian-invite/:token`.

  The visitor has received an email because a student entered their
  address. They land here, sign in (or are already signed in) as a
  parent or teacher, and confirm the link.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Accounts
  alias FunSheep.Accounts.{StudentGuardian, UserRole}
  alias FunSheep.Repo

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    lookup =
      case Accounts.fetch_pending_guardian_invite_by_token(token) do
        {:ok, sg} -> {:ok, Repo.preload(sg, :student)}
        other -> other
      end

    guardian = guardian_from_session(socket)

    socket =
      socket
      |> assign(
        page_title: "Accept guardian invite",
        token: token,
        lookup: lookup,
        guardian: guardian,
        claim_result: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("claim", _params, socket) do
    case {socket.assigns.lookup, socket.assigns.guardian} do
      {{:ok, _sg}, nil} ->
        {:noreply, assign(socket, :claim_result, {:error, :not_signed_in})}

      {{:ok, sg}, %UserRole{role: role} = guardian} when role in [:parent, :teacher] ->
        result = Accounts.claim_guardian_invite_by_token(sg.invite_token || "", guardian)
        {:noreply, assign(socket, :claim_result, result)}

      {{:ok, _sg}, %UserRole{}} ->
        {:noreply, assign(socket, :claim_result, {:error, :not_a_guardian})}

      {_, _} ->
        {:noreply, socket}
    end
  end

  defp guardian_from_session(socket) do
    case socket.assigns[:current_user] do
      %{"interactor_user_id" => iid} when is_binary(iid) ->
        iid
        |> Accounts.list_user_roles_by_interactor_id()
        |> Enum.find(fn ur -> ur.role in [:parent, :teacher] end)

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto px-4 py-8 space-y-6">
      <%= cond do %>
        <% match?({:error, :not_found}, @lookup) -> %>
          <.error_card
            title="Invitation not found"
            body="This link isn't valid. Ask the student to send a fresh invite."
          />
        <% match?({:error, :expired}, @lookup) -> %>
          <.error_card
            title="This invitation has expired"
            body="Invite links are valid for 14 days. Ask the student to send a new one."
          />
        <% match?({:error, :consumed}, @lookup) -> %>
          <.error_card
            title="This invitation has already been accepted"
            body="You can manage your linked students from the Guardians page."
          />
        <% match?({:ok, _}, @claim_result) -> %>
          <.success_card student={student_of(@lookup)} />
        <% match?({:error, :not_signed_in}, @claim_result) -> %>
          <.sign_in_card student={student_of(@lookup)} token={@token} />
        <% match?({:error, :relationship_mismatch}, @claim_result) -> %>
          <.error_card
            title="Wrong account type"
            body="This invite is for a different role. Sign in with the account type the student asked for."
          />
        <% match?({:error, :not_a_guardian}, @claim_result) -> %>
          <.error_card
            title="Sign in with a grown-up account"
            body="Only parent or teacher accounts can accept a grown-up invite."
          />
        <% is_nil(@guardian) -> %>
          <.sign_in_card student={student_of(@lookup)} token={@token} />
        <% true -> %>
          <.confirm_card student={student_of(@lookup)} guardian={@guardian} />
      <% end %>
    </div>
    """
  end

  attr :student, :any, required: true

  defp success_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
      <div class="text-5xl" aria-hidden="true">🎉</div>
      <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white">You're all set</h1>
      <p class="text-sm text-[#1C1C1E] dark:text-white">
        You're now linked with {@student && (@student.display_name || @student.email)}.
        You can follow their progress and unlock more practice.
      </p>
      <.link
        navigate="/dashboard"
        class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
      >
        Go to your dashboard
      </.link>
    </div>
    """
  end

  attr :student, :any, required: true
  attr :guardian, :any, required: true

  defp confirm_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
      <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white">
        Accept invitation
      </h1>
      <p class="text-sm text-[#1C1C1E] dark:text-white">
        {@student && (@student.display_name || @student.email)} invited you to be their
        grown-up on FunSheep.
      </p>
      <button
        phx-click="claim"
        class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
      >
        Accept
      </button>
    </div>
    """
  end

  attr :student, :any, required: true
  attr :token, :string, required: true

  defp sign_in_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
      <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white">
        Sign in to accept
      </h1>
      <p class="text-sm text-[#1C1C1E] dark:text-white">
        {@student && (@student.display_name || @student.email)} invited you to FunSheep.
        Sign in (or create an account) as a parent or teacher to continue.
      </p>
      <.link
        navigate={"/auth/login?return_to=/guardian-invite/#{@token}"}
        class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
      >
        Sign in
      </.link>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :body, :string, required: true

  defp error_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center">
      <h1 class="text-xl font-bold text-[#1C1C1E] dark:text-white mb-2">{@title}</h1>
      <p class="text-sm text-[#8E8E93]">{@body}</p>
    </div>
    """
  end

  defp student_of({:ok, %StudentGuardian{student: student}}), do: student
  defp student_of(_), do: nil
end
