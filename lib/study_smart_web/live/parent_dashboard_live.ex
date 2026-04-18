defmodule StudySmartWeb.ParentDashboardLive do
  use StudySmartWeb, :live_view

  alias StudySmart.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    children =
      case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
        nil ->
          []

        user_role ->
          Accounts.list_students_for_guardian(user_role.id)
          |> Enum.map(fn sg ->
            student = sg.student
            school = if Ecto.assoc_loaded?(student.school) && student.school, do: student.school

            %{
              id: student.id,
              name: student.display_name || student.email,
              email: student.email,
              grade: student.grade,
              school_name: if(school, do: school.name, else: "N/A"),
              readiness_score: nil,
              upcoming_tests: 0,
              nearest_test_date: nil
            }
          end)
      end

    {:ok,
     assign(socket,
       page_title: "Parent Dashboard",
       children: children
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Parent Dashboard</h1>
      <p class="text-[#8E8E93] mt-2">Welcome, {@current_user["display_name"]}</p>

      <%= if @children == [] do %>
        <div class="bg-white rounded-2xl shadow-md p-8 mt-8 text-center">
          <.icon name="hero-users" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
          <p class="text-[#8E8E93] text-lg">
            No children linked yet. Add a child to start monitoring their progress.
          </p>
          <.link
            navigate={~p"/guardians"}
            class="inline-block mt-6 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Child
          </.link>
        </div>
      <% else %>
        <div class="flex justify-end mt-6">
          <.link
            navigate={~p"/guardians"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Child
          </.link>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mt-6">
          <.child_card :for={child <- @children} child={child} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :child, :map, required: true

  defp child_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6">
      <div class="mb-4">
        <h3 class="font-bold text-[#1C1C1E] text-lg">{@child.name}</h3>
        <p class="text-sm text-[#8E8E93]">{@child.school_name}</p>
        <p :if={@child.grade} class="text-sm text-[#8E8E93]">Grade: {@child.grade}</p>
      </div>

      <div class="space-y-3">
        <div class="flex items-center justify-between">
          <span class="text-sm text-[#8E8E93]">Upcoming tests</span>
          <span class="font-semibold text-[#1C1C1E]">{@child.upcoming_tests}</span>
        </div>

        <div :if={@child.nearest_test_date} class="flex items-center justify-between">
          <span class="text-sm text-[#8E8E93]">Nearest test</span>
          <span class="font-semibold text-[#1C1C1E]">{@child.nearest_test_date}</span>
        </div>

        <div>
          <div class="flex items-center justify-between mb-1">
            <span class="text-sm text-[#8E8E93]">Readiness</span>
            <%= if @child.readiness_score do %>
              <span class={"text-sm font-semibold #{readiness_text_color(@child.readiness_score)}"}>
                {@child.readiness_score}%
              </span>
            <% else %>
              <span class="text-sm text-[#8E8E93]">No assessments yet</span>
            <% end %>
          </div>
          <div :if={@child.readiness_score} class="w-full bg-[#F5F5F7] rounded-full h-2">
            <div
              class={"h-2 rounded-full #{readiness_bar_color(@child.readiness_score)}"}
              style={"width: #{@child.readiness_score}%"}
            >
            </div>
          </div>
        </div>
      </div>

      <div class="mt-4 pt-4 border-t border-[#E5E5EA]">
        <.link
          navigate={~p"/guardians"}
          class="text-sm text-[#4CD964] hover:text-[#3DBF55] font-medium"
        >
          View Details
        </.link>
      </div>
    </div>
    """
  end

  defp readiness_bar_color(score) when score > 70, do: "bg-[#4CD964]"
  defp readiness_bar_color(score) when score >= 40, do: "bg-[#FFCC00]"
  defp readiness_bar_color(_score), do: "bg-[#FF3B30]"

  defp readiness_text_color(score) when score > 70, do: "text-[#4CD964]"
  defp readiness_text_color(score) when score >= 40, do: "text-[#FFCC00]"
  defp readiness_text_color(_score), do: "text-[#FF3B30]"
end
