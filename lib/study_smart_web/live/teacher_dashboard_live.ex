defmodule StudySmartWeb.TeacherDashboardLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    students =
      case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
        nil ->
          []

        user_role ->
          Accounts.list_students_for_guardian(user_role.id)
          |> Enum.map(fn sg ->
            student = sg.student

            %{
              id: student.id,
              name: student.display_name || student.email,
              email: student.email,
              grade: student.grade,
              readiness_score: nil,
              last_active: nil
            }
          end)
      end

    {:ok,
     assign(socket,
       page_title: "Teacher Dashboard",
       students: students,
       sort_by: :name,
       sort_dir: :asc
     )}
  end

  @impl true
  def handle_event("sort", %{"field" => "readiness"}, socket) do
    new_dir =
      if socket.assigns.sort_by == :readiness,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :desc

    sorted =
      Enum.sort_by(socket.assigns.students, & &1.readiness_score, fn a, b ->
        case new_dir do
          :asc -> (a || -1) <= (b || -1)
          :desc -> (a || -1) >= (b || -1)
        end
      end)

    {:noreply, assign(socket, students: sorted, sort_by: :readiness, sort_dir: new_dir)}
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  @impl true
  def render(assigns) do
    avg_readiness = calculate_avg_readiness(assigns.students)
    assigns = assign(assigns, :avg_readiness, avg_readiness)

    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Teacher Dashboard</h1>
      <p class="text-[#8E8E93] mt-2">Welcome, {@current_user["display_name"]}</p>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-8">
        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Total Students</h3>
            <.icon name="hero-user-group" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#4CD964]">{length(@students)}</p>
        </div>

        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Average Readiness</h3>
            <.icon name="hero-chart-bar" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <%= if @avg_readiness do %>
            <p class={"text-3xl font-bold #{readiness_text_color(@avg_readiness)}"}>
              {@avg_readiness}%
            </p>
          <% else %>
            <p class="text-3xl font-bold text-[#8E8E93]">N/A</p>
          <% end %>
        </div>
      </div>

      <%= if @students == [] do %>
        <div class="bg-white rounded-2xl shadow-md p-8 mt-8 text-center">
          <.icon name="hero-user-group" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
          <p class="text-[#8E8E93] text-lg">
            No students linked yet. Add students to start monitoring their progress.
          </p>
          <.link
            navigate={~p"/guardians"}
            class="inline-block mt-6 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Students
          </.link>
        </div>
      <% else %>
        <div class="flex justify-end mt-6">
          <.link
            navigate={~p"/guardians"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Students
          </.link>
        </div>

        <div class="bg-white rounded-2xl shadow-md mt-6 overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-[#E5E5EA]">
                <th class="text-left px-6 py-4 text-sm font-semibold text-[#1C1C1E]">Name</th>
                <th class="text-left px-6 py-4 text-sm font-semibold text-[#1C1C1E]">Email</th>
                <th class="text-left px-6 py-4 text-sm font-semibold text-[#1C1C1E]">Grade</th>
                <th
                  class="text-left px-6 py-4 text-sm font-semibold text-[#1C1C1E] cursor-pointer hover:text-[#4CD964]"
                  phx-click="sort"
                  phx-value-field="readiness"
                >
                  Readiness Score
                  <%= if @sort_by == :readiness do %>
                    <span class="ml-1">{if @sort_dir == :asc, do: "\u25B2", else: "\u25BC"}</span>
                  <% end %>
                </th>
                <th class="text-left px-6 py-4 text-sm font-semibold text-[#1C1C1E]">Last Active</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{student, idx} <- Enum.with_index(@students)}
                class={[
                  "border-b border-[#E5E5EA] last:border-0",
                  if(rem(idx, 2) == 1, do: "bg-[#F5F5F7]", else: "bg-white")
                ]}
              >
                <td class="px-6 py-4 text-sm text-[#1C1C1E] font-medium">{student.name}</td>
                <td class="px-6 py-4 text-sm text-[#8E8E93]">{student.email}</td>
                <td class="px-6 py-4 text-sm text-[#8E8E93]">{student.grade || "N/A"}</td>
                <td class="px-6 py-4">
                  <%= if student.readiness_score do %>
                    <span class={"text-xs font-medium px-3 py-1 rounded-full #{readiness_badge(student.readiness_score)}"}>
                      {student.readiness_score}%
                    </span>
                  <% else %>
                    <span class="text-sm text-[#8E8E93]">N/A</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 text-sm text-[#8E8E93]">
                  {student.last_active || "Never"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp calculate_avg_readiness(students) do
    scores = Enum.filter(students, & &1.readiness_score) |> Enum.map(& &1.readiness_score)

    case scores do
      [] -> nil
      scores -> Enum.sum(scores) |> div(length(scores))
    end
  end

  defp readiness_badge(score) when score > 70, do: "bg-[#E8F8EB] text-[#4CD964]"
  defp readiness_badge(score) when score >= 40, do: "bg-[#FFF8E1] text-[#FFCC00]"
  defp readiness_badge(_score), do: "bg-[#FFE5E3] text-[#FF3B30]"

  defp readiness_text_color(score) when score > 70, do: "text-[#4CD964]"
  defp readiness_text_color(score) when score >= 40, do: "text-[#FFCC00]"
  defp readiness_text_color(_score), do: "text-[#FF3B30]"
end
