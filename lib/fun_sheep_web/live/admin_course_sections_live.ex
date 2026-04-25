defmodule FunSheepWeb.AdminCourseSectionsLive do
  @moduledoc """
  Admin page for managing video resources attached to each section of a course.

  Displays the course's chapter → section tree. For each section, admins can
  view existing video resources and add or remove new ones.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, Resources}

  @source_options [
    {"YouTube", :youtube},
    {"Khan Academy", :khan_academy},
    {"Other", :other}
  ]

  @impl true
  def mount(%{"id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    videos = Resources.list_videos_for_course(course_id)
    videos_by_section = Enum.group_by(videos, & &1.section_id)

    {:ok,
     socket
     |> assign(:page_title, "#{course.name} · Sections")
     |> assign(:course, course)
     |> assign(:videos_by_section, videos_by_section)
     |> assign(:selected_section_id, nil)
     |> assign(:form_error, nil)
     |> assign(:source_options, @source_options)}
  end

  @impl true
  def handle_event("select_section", %{"id" => section_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_section_id, section_id)
     |> assign(:form_error, nil)}
  end

  def handle_event("add_video", params, socket) do
    section_id = socket.assigns.selected_section_id

    attrs = %{
      title: Map.get(params, "title", "") |> String.trim(),
      url: Map.get(params, "url", "") |> String.trim(),
      source: Map.get(params, "source", "other"),
      duration_seconds: parse_duration(Map.get(params, "duration_seconds")),
      section_id: section_id,
      course_id: socket.assigns.course.id
    }

    case Resources.create_video_resource(attrs) do
      {:ok, video} ->
        videos_by_section =
          Map.update(
            socket.assigns.videos_by_section,
            section_id,
            [video],
            &(&1 ++ [video])
          )

        {:noreply,
         socket
         |> assign(:videos_by_section, videos_by_section)
         |> assign(:form_error, nil)
         |> put_flash(:info, "Video resource added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_error, changeset_error_summary(changeset))}
    end
  end

  def handle_event("delete_video", %{"id" => video_id}, socket) do
    video = Resources.get_video_resource!(video_id)

    case Resources.delete_video_resource(video) do
      {:ok, _} ->
        videos_by_section =
          Map.update(
            socket.assigns.videos_by_section,
            video.section_id,
            [],
            &Enum.reject(&1, fn v -> v.id == video_id end)
          )

        {:noreply,
         socket
         |> assign(:videos_by_section, videos_by_section)
         |> put_flash(:info, "Video resource removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove video resource.")}
    end
  end

  # ── Private helpers ──

  defp parse_duration(nil), do: nil
  defp parse_duration(""), do: nil

  defp parse_duration(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp changeset_error_summary(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex items-center gap-3 mb-6">
        <.link
          navigate={~p"/admin/courses"}
          class="text-sm text-[#8E8E93] hover:text-[#1C1C1E] flex items-center gap-1"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-4 h-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Courses
        </.link>
        <span class="text-[#E5E5EA]">/</span>
        <h1 class="text-2xl font-bold text-[#1C1C1E]">{@course.name} · Video Resources</h1>
      </div>

      <div class="flex gap-6">
        <%!-- Left: chapter/section tree --%>
        <div class="w-72 flex-shrink-0">
          <div class="bg-white rounded-2xl shadow-md p-4">
            <p class="text-xs font-semibold text-[#8E8E93] uppercase mb-3">Sections</p>
            <div :for={chapter <- @course.chapters} class="mb-4">
              <p class="text-xs font-semibold text-[#1C1C1E] px-2 py-1 bg-[#F5F5F7] rounded-lg mb-1">
                {chapter.name}
              </p>
              <div :for={section <- chapter.sections}>
                <button
                  type="button"
                  phx-click="select_section"
                  phx-value-id={section.id}
                  class={[
                    "w-full text-left text-sm px-3 py-2 rounded-lg transition-colors",
                    if(@selected_section_id == section.id,
                      do: "bg-[#E8F8EB] text-[#1C1C1E] font-medium",
                      else: "text-[#3A3A3C] hover:bg-[#F5F5F7]"
                    )
                  ]}
                >
                  <span class="flex items-center justify-between">
                    <span>{section.name}</span>
                    <span
                      :if={
                        map_size(@videos_by_section) > 0 and
                          length(Map.get(@videos_by_section, section.id, [])) > 0
                      }
                      class="text-xs bg-[#4CD964] text-white rounded-full px-1.5 py-0.5"
                    >
                      {length(Map.get(@videos_by_section, section.id, []))}
                    </span>
                  </span>
                </button>
              </div>
            </div>
            <p
              :if={@course.chapters == []}
              class="text-sm text-[#8E8E93] text-center py-4"
            >
              No chapters found.
            </p>
          </div>
        </div>

        <%!-- Right: section detail + video list + add form --%>
        <div class="flex-1 min-w-0">
          <div
            :if={is_nil(@selected_section_id)}
            class="bg-white rounded-2xl shadow-md p-10 text-center"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="w-12 h-12 text-[#E5E5EA] mx-auto mb-3"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="1.5"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z"
              />
            </svg>
            <p class="text-[#8E8E93] text-sm">
              Select a section on the left to manage its video resources.
            </p>
          </div>

          <div :if={not is_nil(@selected_section_id)}>
            <%!-- Video list --%>
            <div class="bg-white rounded-2xl shadow-md mb-4">
              <div class="px-6 py-4 border-b border-[#F5F5F7]">
                <h2 class="font-semibold text-[#1C1C1E]">Video Resources</h2>
              </div>

              <div
                :if={Map.get(@videos_by_section, @selected_section_id, []) == []}
                class="px-6 py-8 text-center text-sm text-[#8E8E93]"
              >
                No videos added yet.
              </div>

              <div
                :for={video <- Map.get(@videos_by_section, @selected_section_id, [])}
                class="px-6 py-4 border-b border-[#F5F5F7] last:border-0 flex items-start gap-4"
              >
                <div class="flex-1 min-w-0">
                  <p class="font-medium text-[#1C1C1E] truncate">{video.title}</p>
                  <p class="text-sm text-[#8E8E93] truncate">{video.url}</p>
                  <div class="flex items-center gap-3 mt-1">
                    <span class="inline-block px-2 py-0.5 rounded-full text-xs font-medium bg-[#F5F5F7] text-[#3A3A3C]">
                      {video.source |> to_string() |> String.replace("_", " ") |> String.capitalize()}
                    </span>
                    <span class="text-xs text-[#8E8E93]">
                      {format_duration(video.duration_seconds)}
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="delete_video"
                  phx-value-id={video.id}
                  data-confirm="Remove this video resource? This cannot be undone."
                  class="px-3 py-1 rounded-full text-xs font-medium text-[#FF3B30] border border-[#FF3B30]/30 hover:bg-[#FFE5E3] flex-shrink-0"
                >
                  Remove
                </button>
              </div>
            </div>

            <%!-- Add form --%>
            <div class="bg-white rounded-2xl shadow-md">
              <div class="px-6 py-4 border-b border-[#F5F5F7]">
                <h2 class="font-semibold text-[#1C1C1E]">Add Video Resource</h2>
              </div>

              <div
                :if={@form_error}
                class="mx-6 mt-4 px-4 py-3 bg-[#FFE5E3] rounded-xl text-sm text-[#FF3B30]"
              >
                {@form_error}
              </div>

              <.form for={%{}} phx-submit="add_video" class="p-6 space-y-4">
                <div>
                  <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Title</label>
                  <input
                    type="text"
                    name="title"
                    required
                    placeholder="e.g. Mitosis and Meiosis Explained"
                    class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium text-[#1C1C1E] mb-1">URL</label>
                  <input
                    type="url"
                    name="url"
                    required
                    placeholder="https://www.youtube.com/watch?v=..."
                    class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
                  />
                </div>

                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-[#1C1C1E] mb-1">Source</label>
                    <select
                      name="source"
                      class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
                    >
                      <option :for={{label, value} <- @source_options} value={value}>
                        {label}
                      </option>
                    </select>
                  </div>

                  <div>
                    <label class="block text-sm font-medium text-[#1C1C1E] mb-1">
                      Duration (seconds, optional)
                    </label>
                    <input
                      type="number"
                      name="duration_seconds"
                      min="1"
                      placeholder="e.g. 480"
                      class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] focus:bg-white rounded-full outline-none transition-colors"
                    />
                  </div>
                </div>

                <div class="flex justify-end pt-2">
                  <button
                    type="submit"
                    class="px-6 py-2 rounded-full text-sm font-medium text-white bg-[#4CD964] hover:bg-[#3DBF55] shadow-md transition-colors"
                  >
                    Add Video
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
