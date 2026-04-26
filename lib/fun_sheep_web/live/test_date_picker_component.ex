defmodule FunSheepWeb.TestDatePickerComponent do
  @moduledoc """
  LiveComponent for picking a test date.

  Shows official upcoming dates from `known_test_dates` for the course's
  `catalog_test_type`, plus a "Set a custom date" option for teacher-created
  in-class tests (common for AP classes).

  After the student picks a date, it creates a `TestSchedule` record and
  sends `{:test_date_selected, schedule}` to the parent LiveView.
  """

  use FunSheepWeb, :live_component

  alias FunSheep.{Assessments, Courses}
  alias FunSheep.Assessments.TestSchedule

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       showing_custom: false,
       custom_date: "",
       custom_name: "",
       saving: false,
       error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    known_dates =
      if assigns.course.catalog_test_type do
        Courses.list_upcoming_known_dates(assigns.course.catalog_test_type)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(known_dates: known_dates)}
  end

  @impl true
  def handle_event("pick_official_date", %{"known_test_date_id" => known_id}, socket) do
    course = socket.assigns.course
    user_role_id = socket.assigns.user_role_id
    known_date = Enum.find(socket.assigns.known_dates, &(&1.id == known_id))

    if is_nil(known_date) do
      {:noreply, assign(socket, error: "Date not found. Please try again.")}
    else
      attrs = %{
        name: known_date.test_name,
        test_date: known_date.test_date,
        scope: %{"all_chapters" => true},
        user_role_id: user_role_id,
        course_id: course.id,
        schedule_type: :official,
        is_auto_created: false,
        known_test_date_id: known_date.id
      }

      do_create_schedule(socket, attrs)
    end
  end

  def handle_event("show_custom_form", _params, socket) do
    {:noreply, assign(socket, showing_custom: true, error: nil)}
  end

  def handle_event("hide_custom_form", _params, socket) do
    {:noreply, assign(socket, showing_custom: false, custom_date: "", custom_name: "", error: nil)}
  end

  def handle_event("update_custom_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, custom_name: value)}
  end

  def handle_event("update_custom_date", %{"value" => value}, socket) do
    {:noreply, assign(socket, custom_date: value)}
  end

  def handle_event("save_custom_date", _params, socket) do
    course = socket.assigns.course
    user_role_id = socket.assigns.user_role_id
    custom_date = socket.assigns.custom_date
    custom_name = socket.assigns.custom_name

    with {:date, {:ok, date}} <- {:date, Date.from_iso8601(custom_date)},
         {:name, name} when name != "" <- {:name, String.trim(custom_name)} do
      attrs = %{
        name: name,
        test_date: date,
        scope: %{"all_chapters" => true},
        user_role_id: user_role_id,
        course_id: course.id,
        schedule_type: :standard,
        is_auto_created: false
      }

      do_create_schedule(socket, attrs)
    else
      {:date, _} ->
        {:noreply, assign(socket, error: "Please enter a valid date.")}

      {:name, ""} ->
        {:noreply, assign(socket, error: "Please enter a name for the test.")}
    end
  end

  defp do_create_schedule(socket, attrs) do
    socket = assign(socket, saving: true, error: nil)

    case Assessments.create_test_schedule(attrs) do
      {:ok, schedule} ->
        send(self(), {:test_date_selected, schedule})
        {:noreply, assign(socket, saving: false)}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Map.values()
          |> List.flatten()
          |> Enum.join(", ")

        {:noreply, assign(socket, saving: false, error: errors)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 shadow-md overflow-hidden">
      <div class="p-6 border-b border-gray-100">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 bg-[#E8F8EB] rounded-full flex items-center justify-center">
            <.icon name="hero-calendar-days" class="w-5 h-5 text-[#4CD964]" />
          </div>
          <div>
            <h2 class="text-lg font-semibold text-gray-900">When is your test?</h2>
            <p class="text-sm text-gray-500">
              Pick an upcoming date to start tracking your readiness
            </p>
          </div>
        </div>
      </div>

      <div :if={@error} class="mx-6 mt-4 p-3 bg-red-50 border border-red-200 rounded-xl">
        <p class="text-sm text-red-700">{@error}</p>
      </div>

      <%!-- Official dates from organizing body --%>
      <div :if={@known_dates != []} class="p-6 space-y-3">
        <p class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3">
          Official {String.upcase(@course.catalog_test_type || "")} Dates
        </p>

        <button
          :for={kd <- @known_dates}
          type="button"
          phx-click="pick_official_date"
          phx-value-known_test_date_id={kd.id}
          phx-target={@myself}
          disabled={@saving}
          class="w-full text-left p-4 border border-gray-200 rounded-xl hover:border-[#4CD964] hover:bg-[#F5FBF6] transition-colors group"
        >
          <div class="flex items-center justify-between">
            <div>
              <p class="font-medium text-gray-900 group-hover:text-[#2D9E44] text-sm">
                {kd.test_name}
              </p>
              <p class="text-xs text-gray-500 mt-0.5">
                {Calendar.strftime(kd.test_date, "%B %-d, %Y")}
                <span :if={kd.registration_deadline} class="ml-2 text-gray-400">
                  · Reg. deadline: {Calendar.strftime(kd.registration_deadline, "%b %-d")}
                </span>
              </p>
            </div>
            <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-400 group-hover:text-[#4CD964]" />
          </div>
        </button>
      </div>

      <div :if={@known_dates == []} class="p-6">
        <p class="text-sm text-gray-500">
          No upcoming official dates found yet. Use a custom date below.
        </p>
      </div>

      <%!-- Divider --%>
      <div class="mx-6 border-t border-gray-100" />

      <%!-- Custom date option --%>
      <div class="p-6">
        <div :if={!@showing_custom}>
          <button
            type="button"
            phx-click="show_custom_form"
            phx-target={@myself}
            class="w-full text-left p-4 border border-dashed border-gray-300 rounded-xl hover:border-[#4CD964] hover:bg-[#F5FBF6] transition-colors group"
          >
            <div class="flex items-center gap-3">
              <.icon name="hero-plus-circle" class="w-5 h-5 text-gray-400 group-hover:text-[#4CD964]" />
              <div>
                <p class="font-medium text-gray-700 group-hover:text-[#2D9E44] text-sm">
                  Set a custom date
                </p>
                <p class="text-xs text-gray-500 mt-0.5">
                  For in-class tests, school-specific exams, or any other date
                </p>
              </div>
            </div>
          </button>
        </div>

        <div :if={@showing_custom} class="space-y-3">
          <p class="text-sm font-medium text-gray-900">Custom test date</p>

          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Test name</label>
            <input
              type="text"
              phx-change="update_custom_name"
              phx-target={@myself}
              name="value"
              value={@custom_name}
              placeholder="e.g., AP Biology In-Class Practice"
              class="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-full text-sm text-gray-900 focus:border-[#4CD964] outline-none"
            />
          </div>

          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Test date</label>
            <input
              type="date"
              phx-change="update_custom_date"
              phx-target={@myself}
              name="value"
              value={@custom_date}
              min={Date.to_iso8601(Date.utc_today())}
              class="w-full px-4 py-2 bg-gray-50 border border-gray-200 rounded-full text-sm text-gray-900 focus:border-[#4CD964] outline-none"
            />
          </div>

          <div class="flex gap-2 pt-1">
            <button
              type="button"
              phx-click="save_custom_date"
              phx-target={@myself}
              disabled={@saving or @custom_date == "" or @custom_name == ""}
              class="flex-1 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-2 rounded-full text-sm transition-colors disabled:opacity-50"
            >
              {if @saving, do: "Saving...", else: "Set this date"}
            </button>
            <button
              type="button"
              phx-click="hide_custom_form"
              phx-target={@myself}
              class="px-4 py-2 bg-white border border-gray-200 text-gray-700 rounded-full text-sm hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
