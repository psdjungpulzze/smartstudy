defmodule StudySmartWeb.GuardianInviteLive do
  use StudySmartWeb, :live_view

  import Ecto.Query

  alias StudySmart.Accounts

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.current_role
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(page_title: "Guardian Links")
      |> assign(invite_email: "")
      |> assign(invite_error: nil)
      |> assign(invite_success: nil)
      |> load_data(role, user)

    {:ok, socket}
  end

  defp load_data(socket, role, user) when role in ["parent", "teacher"] do
    case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
      nil ->
        assign(socket, user_role: nil, students: [], pending_invites: [])

      user_role ->
        students = Accounts.list_students_for_guardian(user_role.id)

        pending =
          from(sg in StudySmart.Accounts.StudentGuardian,
            where: sg.guardian_id == ^user_role.id and sg.status == :pending,
            preload: [:student]
          )
          |> StudySmart.Repo.all()

        assign(socket, user_role: user_role, students: students, pending_invites: pending)
    end
  end

  defp load_data(socket, "student", user) do
    case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
      nil ->
        assign(socket, user_role: nil, guardians: [], pending_invites: [])

      user_role ->
        guardians = Accounts.list_active_guardians_for_student(user_role.id)
        pending = Accounts.list_pending_invites_for_student(user_role.id)
        assign(socket, user_role: user_role, guardians: guardians, pending_invites: pending)
    end
  end

  defp load_data(socket, _role, _user) do
    assign(socket, user_role: nil, students: [], guardians: [], pending_invites: [])
  end

  @impl true
  def handle_event("invite", %{"email" => email}, socket) do
    role = socket.assigns.current_role
    user_role = socket.assigns.user_role

    relationship_type =
      case role do
        "parent" -> :parent
        "teacher" -> :teacher
        _ -> :parent
      end

    case Accounts.invite_guardian(user_role.id, String.trim(email), relationship_type) do
      {:ok, _sg} ->
        socket =
          socket
          |> assign(invite_email: "", invite_error: nil, invite_success: "Invitation sent!")
          |> load_data(role, socket.assigns.current_user)

        {:noreply, socket}

      {:error, :student_not_found} ->
        {:noreply,
         assign(socket, invite_error: "No student found with that email.", invite_success: nil)}

      {:error, :already_linked} ->
        {:noreply,
         assign(socket, invite_error: "Already linked to this student.", invite_success: nil)}

      {:error, :already_invited} ->
        {:noreply,
         assign(socket, invite_error: "Invitation already pending.", invite_success: nil)}

      {:error, _changeset} ->
        {:noreply,
         assign(socket, invite_error: "Failed to send invitation.", invite_success: nil)}
    end
  end

  def handle_event("accept", %{"id" => id}, socket) do
    case Accounts.accept_guardian_invite(id) do
      {:ok, _sg} ->
        socket = load_data(socket, socket.assigns.current_role, socket.assigns.current_user)
        {:noreply, put_flash(socket, :info, "Invitation accepted.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not accept invitation.")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    case Accounts.reject_guardian_invite(id) do
      {:ok, _sg} ->
        socket = load_data(socket, socket.assigns.current_role, socket.assigns.current_user)
        {:noreply, put_flash(socket, :info, "Invitation rejected.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not reject invitation.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Accounts.revoke_guardian(id) do
      {:ok, _sg} ->
        socket = load_data(socket, socket.assigns.current_role, socket.assigns.current_user)
        {:noreply, put_flash(socket, :info, "Link revoked.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not revoke link.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Guardian Links</h1>
      <p class="text-[#8E8E93] mt-2">
        Manage student-guardian relationships.
      </p>

      <%= if @current_role in ["parent", "teacher"] do %>
        <.guardian_view
          user_role={@user_role}
          students={@students}
          pending_invites={@pending_invites}
          invite_email={@invite_email}
          invite_error={@invite_error}
          invite_success={@invite_success}
          current_role={@current_role}
        />
      <% else %>
        <.student_view
          user_role={@user_role}
          guardians={assigns[:guardians] || []}
          pending_invites={@pending_invites}
        />
      <% end %>
    </div>
    """
  end

  attr :user_role, :any, required: true
  attr :students, :list, required: true
  attr :pending_invites, :list, required: true
  attr :invite_email, :string, required: true
  attr :invite_error, :string, default: nil
  attr :invite_success, :string, default: nil
  attr :current_role, :string, required: true

  defp guardian_view(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Invite a Student</h2>
        <form phx-submit="invite" class="flex gap-3 items-start">
          <div class="flex-1">
            <input
              type="email"
              name="email"
              value={@invite_email}
              placeholder="Student's email address"
              required
              class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors"
            />
            <p :if={@invite_error} class="text-sm text-[#FF3B30] mt-2 px-4">{@invite_error}</p>
            <p :if={@invite_success} class="text-sm text-[#4CD964] mt-2 px-4">{@invite_success}</p>
          </div>
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
          >
            Send Invite
          </button>
        </form>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Pending Invitations</h2>
        <%= if @pending_invites == [] do %>
          <p class="text-[#8E8E93]">No pending invitations.</p>
        <% else %>
          <div class="space-y-3">
            <div
              :for={sg <- @pending_invites}
              class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
            >
              <div>
                <p class="font-medium text-[#1C1C1E]">
                  {sg.student.display_name || sg.student.email}
                </p>
                <p class="text-sm text-[#8E8E93]">{sg.student.email}</p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs font-medium px-3 py-1 rounded-full bg-[#FFCC00] text-[#1C1C1E]">
                  Pending
                </span>
                <button
                  phx-click="revoke"
                  phx-value-id={sg.id}
                  class="text-sm text-[#FF3B30] hover:underline"
                >
                  Revoke
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Linked Students</h2>
        <%= if @students == [] do %>
          <p class="text-[#8E8E93]">No students linked yet.</p>
        <% else %>
          <div class="space-y-3">
            <div
              :for={sg <- @students}
              class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
            >
              <div>
                <p class="font-medium text-[#1C1C1E]">
                  {sg.student.display_name || sg.student.email}
                </p>
                <p class="text-sm text-[#8E8E93]">{sg.student.email}</p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs font-medium px-3 py-1 rounded-full bg-[#E8F8EB] text-[#4CD964]">
                  Active
                </span>
                <button
                  phx-click="revoke"
                  phx-value-id={sg.id}
                  class="text-sm text-[#FF3B30] hover:underline"
                >
                  Revoke
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :user_role, :any, required: true
  attr :guardians, :list, required: true
  attr :pending_invites, :list, required: true

  defp student_view(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Pending Invitations</h2>
        <%= if @pending_invites == [] do %>
          <p class="text-[#8E8E93]">No pending invitations.</p>
        <% else %>
          <div class="space-y-3">
            <div
              :for={sg <- @pending_invites}
              class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
            >
              <div>
                <p class="font-medium text-[#1C1C1E]">
                  {sg.guardian.display_name || sg.guardian.email}
                </p>
                <p class="text-sm text-[#8E8E93]">{sg.guardian.email} - {sg.relationship_type}</p>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="accept"
                  phx-value-id={sg.id}
                  class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
                >
                  Accept
                </button>
                <button
                  phx-click="reject"
                  phx-value-id={sg.id}
                  class="bg-white hover:bg-gray-50 text-[#1C1C1E] font-medium px-4 py-2 rounded-full shadow-sm border border-gray-200 transition-colors text-sm"
                >
                  Reject
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">My Guardians</h2>
        <%= if @guardians == [] do %>
          <p class="text-[#8E8E93]">No guardians linked yet.</p>
        <% else %>
          <div class="space-y-3">
            <div
              :for={sg <- @guardians}
              class="flex items-center justify-between p-4 bg-[#F5F5F7] rounded-xl"
            >
              <div>
                <p class="font-medium text-[#1C1C1E]">
                  {sg.guardian.display_name || sg.guardian.email}
                </p>
                <p class="text-sm text-[#8E8E93]">{sg.guardian.email} - {sg.relationship_type}</p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs font-medium px-3 py-1 rounded-full bg-[#E8F8EB] text-[#4CD964]">
                  Active
                </span>
                <button
                  phx-click="revoke"
                  phx-value-id={sg.id}
                  class="text-sm text-[#FF3B30] hover:underline"
                >
                  Revoke
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
