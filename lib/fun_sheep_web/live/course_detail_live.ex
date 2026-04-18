defmodule FunSheepWeb.CourseDetailLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Courses
  alias FunSheep.Courses.{Chapter, Section}

  @impl true
  def mount(%{"id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)

    {:ok,
     assign(socket,
       page_title: course.name,
       course: course,
       chapter_form: nil,
       section_form: nil,
       editing_chapter: nil,
       editing_section: nil,
       expanded_chapters: MapSet.new()
     )}
  end

  @impl true
  def handle_event("toggle_chapter", %{"id" => chapter_id}, socket) do
    expanded = socket.assigns.expanded_chapters

    expanded =
      if MapSet.member?(expanded, chapter_id) do
        MapSet.delete(expanded, chapter_id)
      else
        MapSet.put(expanded, chapter_id)
      end

    {:noreply, assign(socket, expanded_chapters: expanded)}
  end

  ## Chapter events

  def handle_event("show_add_chapter", _params, socket) do
    changeset = Courses.change_chapter(%Chapter{})
    {:noreply, assign(socket, chapter_form: to_form(changeset))}
  end

  def handle_event("cancel_chapter", _params, socket) do
    {:noreply, assign(socket, chapter_form: nil, editing_chapter: nil)}
  end

  def handle_event("save_chapter", %{"chapter" => chapter_params}, socket) do
    course = socket.assigns.course
    position = Courses.next_chapter_position(course.id)

    attrs =
      chapter_params
      |> Map.put("course_id", course.id)
      |> Map.put("position", position)

    case Courses.create_chapter(attrs) do
      {:ok, _chapter} ->
        course = Courses.get_course_with_chapters!(course.id)

        {:noreply,
         socket
         |> assign(course: course, chapter_form: nil)
         |> put_flash(:info, "Chapter added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, chapter_form: to_form(changeset))}
    end
  end

  def handle_event("edit_chapter", %{"id" => chapter_id}, socket) do
    chapter = Courses.get_chapter!(chapter_id)
    changeset = Courses.change_chapter(chapter)
    {:noreply, assign(socket, editing_chapter: chapter_id, chapter_form: to_form(changeset))}
  end

  def handle_event("update_chapter", %{"chapter" => chapter_params}, socket) do
    chapter = Courses.get_chapter!(socket.assigns.editing_chapter)

    case Courses.update_chapter(chapter, chapter_params) do
      {:ok, _chapter} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)

        {:noreply,
         socket
         |> assign(course: course, editing_chapter: nil, chapter_form: nil)
         |> put_flash(:info, "Chapter updated")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, chapter_form: to_form(changeset))}
    end
  end

  def handle_event("delete_chapter", %{"id" => chapter_id}, socket) do
    chapter = Courses.get_chapter!(chapter_id)

    case Courses.delete_chapter(chapter) do
      {:ok, _} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)
        {:noreply, socket |> assign(course: course) |> put_flash(:info, "Chapter deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete chapter")}
    end
  end

  def handle_event("move_chapter_up", %{"id" => chapter_id}, socket) do
    reorder_chapter(socket, chapter_id, :up)
  end

  def handle_event("move_chapter_down", %{"id" => chapter_id}, socket) do
    reorder_chapter(socket, chapter_id, :down)
  end

  ## Section events

  def handle_event("show_add_section", %{"chapter-id" => chapter_id}, socket) do
    changeset = Courses.change_section(%Section{})

    {:noreply,
     assign(socket,
       section_form: to_form(changeset),
       section_chapter_id: chapter_id,
       expanded_chapters: MapSet.put(socket.assigns.expanded_chapters, chapter_id)
     )}
  end

  def handle_event("cancel_section", _params, socket) do
    {:noreply, assign(socket, section_form: nil, editing_section: nil)}
  end

  def handle_event("save_section", %{"section" => section_params}, socket) do
    chapter_id = socket.assigns.section_chapter_id
    position = Courses.next_section_position(chapter_id)

    attrs =
      section_params
      |> Map.put("chapter_id", chapter_id)
      |> Map.put("position", position)

    case Courses.create_section(attrs) do
      {:ok, _section} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)

        {:noreply,
         socket
         |> assign(course: course, section_form: nil)
         |> put_flash(:info, "Section added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, section_form: to_form(changeset))}
    end
  end

  def handle_event("edit_section", %{"id" => section_id}, socket) do
    section = Courses.get_section!(section_id)
    changeset = Courses.change_section(section)
    {:noreply, assign(socket, editing_section: section_id, section_form: to_form(changeset))}
  end

  def handle_event("update_section", %{"section" => section_params}, socket) do
    section = Courses.get_section!(socket.assigns.editing_section)

    case Courses.update_section(section, section_params) do
      {:ok, _section} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)

        {:noreply,
         socket
         |> assign(course: course, editing_section: nil, section_form: nil)
         |> put_flash(:info, "Section updated")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, section_form: to_form(changeset))}
    end
  end

  def handle_event("delete_section", %{"id" => section_id}, socket) do
    section = Courses.get_section!(section_id)

    case Courses.delete_section(section) do
      {:ok, _} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)
        {:noreply, socket |> assign(course: course) |> put_flash(:info, "Section deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete section")}
    end
  end

  ## Private helpers

  defp reorder_chapter(socket, chapter_id, direction) do
    course = socket.assigns.course
    chapters = course.chapters
    index = Enum.find_index(chapters, &(&1.id == chapter_id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(chapters) - 1, index + 1)
      end

    if index != new_index do
      chapter_ids =
        chapters
        |> List.delete_at(index)
        |> List.insert_at(new_index, Enum.at(chapters, index))
        |> Enum.map(& &1.id)

      Courses.reorder_chapters(course.id, chapter_ids)
      course = Courses.get_course_with_chapters!(course.id)
      {:noreply, assign(socket, course: course)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Breadcrumb --%>
      <div class="mb-6">
        <.link
          navigate={~p"/courses"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm inline-flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to Courses
        </.link>
      </div>

      <%!-- Course Info --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-2xl font-bold text-[#1C1C1E]">{@course.name}</h1>
            <div class="flex gap-3 mt-2">
              <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-[#E8F8EB] text-[#3DBF55]">
                {@course.subject}
              </span>
              <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-50 text-blue-600">
                Grade {@course.grade}
              </span>
              <span
                :if={@course.school}
                class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
              >
                <.icon name="hero-building-library" class="w-3 h-3 mr-1" /> {@course.school.name}
              </span>
            </div>
            <p :if={@course.description} class="text-sm text-[#8E8E93] mt-3">{@course.description}</p>
          </div>
          <.link
            navigate={~p"/courses/#{@course.id}/questions"}
            class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-4 py-2 rounded-full border border-gray-200 shadow-sm transition-colors text-sm whitespace-nowrap"
          >
            <.icon name="hero-question-mark-circle" class="w-4 h-4 inline mr-1" /> Question Bank
          </.link>
        </div>
      </div>

      <%!-- Chapters --%>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-[#1C1C1E]">Chapters</h2>
          <button
            :if={@chapter_form == nil || @editing_chapter != nil}
            phx-click="show_add_chapter"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Add Chapter
          </button>
        </div>

        <%!-- Add chapter form --%>
        <div :if={@chapter_form && @editing_chapter == nil} class="bg-white rounded-2xl shadow-md p-4">
          <.form for={@chapter_form} phx-submit="save_chapter" class="flex gap-3 items-end">
            <div class="flex-1">
              <.input
                field={@chapter_form[:name]}
                type="text"
                label="Chapter Name"
                placeholder="e.g. Chapter 1: Introduction"
                required
              />
            </div>
            <div class="flex gap-2 pb-2">
              <button
                type="submit"
                class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel_chapter"
                class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-4 py-2 rounded-full border border-gray-200 shadow-sm transition-colors text-sm"
              >
                Cancel
              </button>
            </div>
          </.form>
        </div>

        <%!-- Chapter list --%>
        <div :if={@course.chapters == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
          <.icon name="hero-book-open" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
          <p class="text-[#8E8E93]">No chapters yet. Add your first chapter above.</p>
        </div>

        <div
          :for={{chapter, idx} <- Enum.with_index(@course.chapters)}
          class="bg-white rounded-2xl shadow-md overflow-hidden"
        >
          <%!-- Chapter header --%>
          <div class="flex items-center px-4 py-3 border-b border-[#E5E5EA]">
            <button
              phx-click="toggle_chapter"
              phx-value-id={chapter.id}
              class="mr-3 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
              aria-label="Toggle chapter sections"
            >
              <.icon
                name={
                  if MapSet.member?(@expanded_chapters, chapter.id),
                    do: "hero-chevron-down",
                    else: "hero-chevron-right"
                }
                class="w-5 h-5"
              />
            </button>

            <%= if @editing_chapter == chapter.id do %>
              <.form
                for={@chapter_form}
                phx-submit="update_chapter"
                class="flex-1 flex gap-3 items-end"
              >
                <div class="flex-1">
                  <.input field={@chapter_form[:name]} type="text" required />
                </div>
                <div class="flex gap-2 pb-2">
                  <button
                    type="submit"
                    class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-3 py-1 rounded-full text-sm transition-colors"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_chapter"
                    class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            <% else %>
              <div class="flex-1">
                <span class="font-semibold text-[#1C1C1E]">{chapter.name}</span>
                <span class="text-xs text-[#8E8E93] ml-2">
                  {length(chapter.sections)} section(s)
                </span>
              </div>
              <div class="flex items-center gap-1">
                <button
                  :if={idx > 0}
                  phx-click="move_chapter_up"
                  phx-value-id={chapter.id}
                  class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
                  aria-label="Move up"
                >
                  <.icon name="hero-arrow-up" class="w-4 h-4" />
                </button>
                <button
                  :if={idx < length(@course.chapters) - 1}
                  phx-click="move_chapter_down"
                  phx-value-id={chapter.id}
                  class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
                  aria-label="Move down"
                >
                  <.icon name="hero-arrow-down" class="w-4 h-4" />
                </button>
                <button
                  phx-click="show_add_section"
                  phx-value-chapter-id={chapter.id}
                  class="p-1 text-[#4CD964] hover:text-[#3DBF55] transition-colors"
                  aria-label="Add section"
                >
                  <.icon name="hero-plus" class="w-4 h-4" />
                </button>
                <button
                  phx-click="edit_chapter"
                  phx-value-id={chapter.id}
                  class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
                  aria-label="Edit chapter"
                >
                  <.icon name="hero-pencil" class="w-4 h-4" />
                </button>
                <button
                  phx-click="delete_chapter"
                  phx-value-id={chapter.id}
                  data-confirm="Delete this chapter and all its sections?"
                  class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
                  aria-label="Delete chapter"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            <% end %>
          </div>

          <%!-- Sections (expandable) --%>
          <div :if={MapSet.member?(@expanded_chapters, chapter.id)} class="bg-gray-50">
            <div
              :for={section <- chapter.sections}
              class="flex items-center px-8 py-2 border-b border-[#E5E5EA] last:border-b-0"
            >
              <%= if @editing_section == section.id do %>
                <.form
                  for={@section_form}
                  phx-submit="update_section"
                  class="flex-1 flex gap-3 items-end"
                >
                  <div class="flex-1">
                    <.input field={@section_form[:name]} type="text" required />
                  </div>
                  <div class="flex gap-2 pb-2">
                    <button
                      type="submit"
                      class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-3 py-1 rounded-full text-sm transition-colors"
                    >
                      Save
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_section"
                      class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm transition-colors"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              <% else %>
                <span class="flex-1 text-sm text-[#1C1C1E]">
                  <.icon name="hero-document" class="w-4 h-4 inline mr-1 text-[#8E8E93]" />
                  {section.name}
                </span>
                <div class="flex items-center gap-1">
                  <button
                    phx-click="edit_section"
                    phx-value-id={section.id}
                    class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
                    aria-label="Edit section"
                  >
                    <.icon name="hero-pencil" class="w-3 h-3" />
                  </button>
                  <button
                    phx-click="delete_section"
                    phx-value-id={section.id}
                    data-confirm="Delete this section?"
                    class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
                    aria-label="Delete section"
                  >
                    <.icon name="hero-trash" class="w-3 h-3" />
                  </button>
                </div>
              <% end %>
            </div>

            <%!-- Add section form (inline) --%>
            <div
              :if={
                @section_form && @editing_section == nil && assigns[:section_chapter_id] == chapter.id
              }
              class="px-8 py-3 border-t border-[#E5E5EA]"
            >
              <.form for={@section_form} phx-submit="save_section" class="flex gap-3 items-end">
                <div class="flex-1">
                  <.input
                    field={@section_form[:name]}
                    type="text"
                    placeholder="Section name..."
                    required
                  />
                </div>
                <div class="flex gap-2 pb-2">
                  <button
                    type="submit"
                    class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-3 py-1 rounded-full text-sm transition-colors"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_section"
                    class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>

            <div
              :if={
                chapter.sections == [] &&
                  !(@section_form && assigns[:section_chapter_id] == chapter.id)
              }
              class="px-8 py-4 text-center"
            >
              <p class="text-sm text-[#8E8E93]">No sections yet</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
