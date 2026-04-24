defmodule FunSheepWeb.PracticeRequestLive.AskComponent do
  @moduledoc """
  Encapsulates the student-side surfaces of Flow A (§4):

    * Usage meter (dashboard card variant)
    * 85% Ask card → opens the request-builder modal
    * Request-builder modal (§4.4) → `PracticeRequests.create/3`
    * Waiting card shown after the request has been sent (§4.5)

  Embed on any student-facing page with `student_id` (UserRole id):

      <.live_component
        module={FunSheepWeb.PracticeRequestLive.AskComponent}
        id="practice-request-ask"
        student_id={@current_user["id"]}
      />

  The component manages its own state and events — the host LV needs
  no Flow A handlers.
  """

  use FunSheepWeb, :live_component

  alias FunSheep.Accounts
  alias FunSheep.Billing
  alias FunSheep.PracticeRequests
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheepWeb.BillingComponents

  @impl true
  def update(assigns, socket) do
    student_id = assigns.student_id

    socket =
      socket
      |> assign(assigns)
      |> assign_flow_state(student_id)

    {:ok, socket}
  end

  defp assign_flow_state(socket, nil) do
    assign(socket,
      state: :not_applicable,
      weekly: %{used: 0, limit: 20, remaining: 20, resets_at: nil},
      paid_stats: %{questions: 0, correct: 0},
      guardians: [],
      pending_request: nil,
      show_modal: false,
      selected_guardian_id: nil,
      selected_reason: nil,
      reason_text: "",
      error: nil
    )
  end

  defp assign_flow_state(socket, student_id) do
    state = Billing.usage_state(student_id)
    weekly = Billing.weekly_usage(student_id)
    guardians = Accounts.list_active_guardian_roles_for_student(student_id, only: :parent)
    pending = fetch_pending(student_id)

    paid_stats =
      if state == :paid,
        do: Billing.paid_weekly_stats(student_id),
        else: %{questions: 0, correct: 0}

    socket
    |> assign(
      state: state,
      weekly: weekly,
      paid_stats: paid_stats,
      guardians: guardians,
      pending_request: pending,
      show_modal: socket.assigns[:show_modal] || false,
      selected_guardian_id:
        socket.assigns[:selected_guardian_id] ||
          (length(guardians) == 1 && hd(guardians).id) || nil,
      selected_reason: socket.assigns[:selected_reason] || nil,
      reason_text: socket.assigns[:reason_text] || "",
      error: socket.assigns[:error] || nil
    )
  end

  defp fetch_pending(student_id) do
    import Ecto.Query

    from(r in Request,
      where: r.student_id == ^student_id and r.status in [:pending, :viewed],
      order_by: [desc: r.sent_at],
      limit: 1,
      preload: [:guardian]
    )
    |> Repo.one()
  end

  @impl true
  def handle_event("open_ask_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: true, error: nil)}
  end

  def handle_event("close_ask_modal", _params, socket) do
    {:noreply,
     assign(socket, show_modal: false, selected_reason: nil, reason_text: "", error: nil)}
  end

  def handle_event("select_reason", %{"code" => code}, socket) do
    {:noreply, assign(socket, selected_reason: String.to_existing_atom(code))}
  end

  def handle_event("submit_request", params, socket) do
    guardian_id =
      params["guardian_id"] ||
        socket.assigns.selected_guardian_id ||
        (List.first(socket.assigns.guardians) || %{}).id

    reason_code =
      case params["reason_code"] || socket.assigns.selected_reason do
        atom when is_atom(atom) -> atom
        str when is_binary(str) -> String.to_existing_atom(str)
        _ -> nil
      end

    reason_text = params["reason_text"] || socket.assigns.reason_text

    case PracticeRequests.create(socket.assigns.student_id, guardian_id, %{
           reason_code: reason_code,
           reason_text: reason_text
         }) do
      {:ok, _request} ->
        socket =
          socket
          |> assign_flow_state(socket.assigns.student_id)
          |> assign(show_modal: false, selected_reason: nil, reason_text: "")

        {:noreply, socket}

      {:error, :already_pending} ->
        {:noreply, assign(socket, error: "You already have a pending ask. Give them a moment.")}

      {:error, :decline_cooldown} ->
        {:noreply,
         assign(socket, error: "Your grown-up just replied — try again in a day or two.")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Couldn't send. Pick a reason and try again.")}
    end
  end

  def handle_event("send_reminder", _params, socket) do
    case socket.assigns.pending_request do
      %Request{id: id} ->
        _ = PracticeRequests.send_reminder(id)
        {:noreply, assign_flow_state(socket, socket.assigns.student_id)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= case @state do %>
        <% :not_applicable -> %>
          <%!-- Nothing — not a student --%>
        <% :paid -> %>
          <BillingComponents.usage_meter
            state={:paid}
            variant={:card}
            questions={@paid_stats.questions}
            correct={@paid_stats.correct}
          />
        <% _ -> %>
          <BillingComponents.usage_meter
            state={@state}
            used={@weekly.used}
            limit={@weekly.limit}
            remaining={@weekly.remaining}
            resets_at={@weekly.resets_at}
            variant={:card}
          />

          <%!-- Ask card only in :ask state, no pending request, and with at least one guardian --%>
          <div :if={@state == :ask and is_nil(@pending_request) and @guardians != []}>
            <BillingComponents.ask_card target={@myself} />
          </div>

          <%!-- Also render at :hardwall for the soft hard-wall surface --%>
          <div :if={@state == :hardwall and is_nil(@pending_request) and @guardians != []}>
            <BillingComponents.ask_card target={@myself} />
          </div>

          <%!-- No linked guardian — invite-a-grown-up placeholder (full flow in §4.8 PR 4) --%>
          <div
            :if={@state in [:ask, :hardwall] and is_nil(@pending_request) and @guardians == []}
            class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6"
          >
            <h3 class="text-lg font-semibold text-[#1C1C1E] dark:text-white mb-2">
              No grown-up linked yet
            </h3>
            <p class="text-sm text-[#8E8E93] mb-4">
              Link a parent or guardian so they can unlock unlimited practice for you.
            </p>
            <.link
              navigate="/guardians"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
            >
              Invite a grown-up
            </.link>
          </div>

          <div :if={@pending_request}>
            <BillingComponents.waiting_card
              guardian_name={guardian_display_name(@pending_request)}
              sent_at={@pending_request.sent_at}
              reminder_sent={not is_nil(@pending_request.reminder_sent_at)}
              can_remind={reminder_window_open?(@pending_request)}
              target={@myself}
            />
          </div>
      <% end %>

      <BillingComponents.ask_modal
        show={@show_modal}
        guardians={@guardians}
        selected_guardian_id={@selected_guardian_id}
        selected_reason={@selected_reason}
        reason_text={@reason_text}
        error={@error}
        target={@myself}
      />
    </div>
    """
  end

  defp guardian_display_name(%Request{guardian: %{display_name: name}}) when is_binary(name),
    do: name

  defp guardian_display_name(_), do: "your grown-up"

  # §4.5 — reminder becomes available after 24h of no response.
  defp reminder_window_open?(%Request{sent_at: sent_at}) when not is_nil(sent_at) do
    DateTime.diff(DateTime.utc_now(), sent_at, :second) >= 24 * 3600
  end

  defp reminder_window_open?(_), do: false
end
