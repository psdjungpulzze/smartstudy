defmodule FunSheepWeb.FixedTests.StartLive do
  @moduledoc """
  Entry point for taking a custom test. Creates a new session and redirects.
  Also handles the assignment flow (assign bank to students).
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, FixedTests}

  @impl true
  def mount(%{"id" => bank_id} = params, _session, socket) do
    user = socket.assigns.current_user
    user_role = Accounts.get_user_role_by_interactor_id(user["interactor_user_id"])

    bank = FixedTests.get_bank_with_questions!(bank_id)

    action = Map.get(params, "action", "start")

    socket =
      socket
      |> assign(bank: bank, user_role: user_role, page_title: bank.title)
      |> assign(action: action)
      |> assign(assign_form: build_assign_form())
      |> assign(students: list_students(user_role))
      |> assign(selected_students: [])

    {:ok, socket}
  end

  @impl true
  def handle_event("start_test", _params, socket) do
    bank = socket.assigns.bank
    user_role = socket.assigns.user_role
    assignment = find_assignment(bank.id, user_role.id)

    cond do
      !FixedTests.within_attempt_limit?(bank, user_role.id) ->
        {:noreply, put_flash(socket, :error, "You have reached the maximum number of attempts")}

      true ->
        assignment_id = assignment && assignment.id

        case FixedTests.start_session(bank.id, user_role.id, assignment_id) do
          {:ok, session} ->
            {:noreply, push_navigate(socket, to: ~p"/custom-tests/session/#{session.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not start test")}
        end
    end
  end

  def handle_event("toggle_student", %{"id" => student_id}, socket) do
    selected = socket.assigns.selected_students

    new_selected =
      if student_id in selected,
        do: List.delete(selected, student_id),
        else: [student_id | selected]

    {:noreply, assign(socket, selected_students: new_selected)}
  end

  def handle_event("assign", %{"due_at" => due_at_str, "note" => note}, socket) do
    bank = socket.assigns.bank
    user_role = socket.assigns.user_role
    student_ids = socket.assigns.selected_students

    if student_ids == [] do
      {:noreply, put_flash(socket, :error, "Select at least one student")}
    else
      due_at = parse_due_at(due_at_str)
      opts = [due_at: due_at, note: note]

      case FixedTests.assign_bank(bank, user_role.id, student_ids, opts) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Assigned to #{length(student_ids)} student(s)")
           |> push_navigate(to: ~p"/custom-tests/#{bank.id}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Assignment failed")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4">
      <%= if @action == "assign" do %>
        <.assign_panel
          bank={@bank}
          students={@students}
          selected={@selected_students}
          form={@assign_form}
        />
      <% else %>
        <.start_panel bank={@bank} user_role={@user_role} />
      <% end %>
    </div>
    """
  end

  defp start_panel(assigns) do
    questions_count = length(assigns.bank.questions)
    attempts = FixedTests.completed_attempts_count(assigns.bank.id, assigns.user_role.id)
    assigns = assign(assigns, questions_count: questions_count, attempts: attempts)

    ~H"""
    <div class="bg-white rounded-2xl shadow-sm p-8 text-center">
      <div class="inline-block bg-indigo-100 text-indigo-700 text-xs font-medium px-3 py-1 rounded-full mb-4">
        Custom Test
      </div>
      <h1 class="text-2xl font-bold text-[#1C1C1E] mb-2">{@bank.title}</h1>
      <%= if @bank.description do %>
        <p class="text-[#8E8E93] mb-4">{@bank.description}</p>
      <% end %>

      <div class="flex justify-center gap-6 text-sm text-[#8E8E93] mb-8">
        <span>{@questions_count} question{if @questions_count != 1, do: "s"}</span>
        <%= if @bank.time_limit_minutes do %>
          <span>⏱ {@bank.time_limit_minutes} min</span>
        <% else %>
          <span>⏱ Untimed</span>
        <% end %>
        <%= if @attempts > 0 do %>
          <span>Attempt #{@attempts + 1}</span>
        <% end %>
      </div>

      <div class="flex flex-col items-center gap-3">
        <button
          phx-click="start_test"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-10 py-3 rounded-full text-lg shadow-md"
        >
          Start Test
        </button>
        <.link navigate={~p"/custom-tests"} class="text-sm text-[#8E8E93] hover:underline">
          Back
        </.link>
      </div>
    </div>
    """
  end

  defp assign_panel(assigns) do
    ~H"""
    <div>
      <.link navigate={~p"/custom-tests/#{@bank.id}"} class="text-sm text-[#8E8E93] hover:underline">
        ← Back to test
      </.link>
      <h1 class="text-2xl font-bold text-[#1C1C1E] mt-3 mb-6">Assign "{@bank.title}"</h1>

      <form phx-submit="assign" class="space-y-6">
        <div class="bg-white rounded-2xl shadow-sm p-5">
          <h2 class="font-semibold mb-3">Select students</h2>

          <%= if @students == [] do %>
            <p class="text-[#8E8E93] text-sm">No students linked to your account yet.</p>
          <% else %>
            <div class="space-y-2">
              <%= for s <- @students do %>
                <label class="flex items-center gap-3 cursor-pointer p-2 rounded-xl hover:bg-gray-50">
                  <input
                    type="checkbox"
                    phx-click="toggle_student"
                    phx-value-id={s.id}
                    checked={s.id in @selected}
                    class="accent-[#4CD964]"
                  />
                  <div>
                    <p class="font-medium text-[#1C1C1E]">{s.display_name || s.email}</p>
                    <p class="text-xs text-[#8E8E93]">{s.email}</p>
                  </div>
                </label>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="bg-white rounded-2xl shadow-sm p-5 space-y-4">
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Due date (optional)</label>
            <input
              type="datetime-local"
              name="due_at"
              class="border border-gray-200 rounded-lg px-3 py-2 text-sm w-full"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-1">
              Note for students (optional)
            </label>
            <textarea
              name="note"
              rows="2"
              placeholder="e.g. Focus on chapters 5–7"
              class="border border-gray-200 rounded-lg px-3 py-2 text-sm w-full resize-none"
            ></textarea>
          </div>
        </div>

        <div class="flex gap-3">
          <button
            type="submit"
            class="bg-indigo-600 hover:bg-indigo-700 text-white font-medium px-6 py-2 rounded-full"
          >
            Assign to {@selected |> length()} student{if length(@selected) != 1, do: "s"}
          </button>
          <.link navigate={~p"/custom-tests/#{@bank.id}"} class="text-[#8E8E93] px-4 py-2">
            Cancel
          </.link>
        </div>
      </form>
    </div>
    """
  end

  defp list_students(nil), do: []

  defp list_students(user_role) do
    user_role.id
    |> Accounts.list_students_for_guardian()
    |> Enum.map(& &1.student)
  end

  defp find_assignment(bank_id, user_role_id) do
    import Ecto.Query
    alias FunSheep.Repo
    alias FunSheep.FixedTests.FixedTestAssignment

    from(a in FixedTestAssignment,
      where: a.bank_id == ^bank_id and a.assigned_to_id == ^user_role_id,
      limit: 1
    )
    |> Repo.one()
  end

  defp build_assign_form, do: %{}

  defp parse_due_at(""), do: nil

  defp parse_due_at(str) do
    case DateTime.from_iso8601(str <> ":00Z") do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
