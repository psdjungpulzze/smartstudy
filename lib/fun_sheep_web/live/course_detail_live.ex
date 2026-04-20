defmodule FunSheepWeb.CourseDetailLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.ShareButton

  alias FunSheep.{Assessments, Content, Courses, Questions}
  alias FunSheep.Courses.{Chapter, Section}

  @impl true
  def mount(%{"id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    user_role_id = socket.assigns.current_user && socket.assigns.current_user["user_role_id"]

    # Subscribe to processing updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "course:#{course_id}")
    end

    {upcoming, past} = load_test_schedules(user_role_id, course_id)
    discovered_sources = Content.list_discovered_sources(course_id)
    question_count = Questions.count_questions_by_course(course_id)

    # Materials: course-linked + unlinked (staged uploads not yet processed)
    {materials, has_pending} =
      if user_role_id do
        course_mats = Content.list_materials_by_course_for_user(course_id, user_role_id)
        unlinked = Content.list_unlinked_materials_for_user(user_role_id)
        all = course_mats ++ unlinked
        pending = Enum.any?(all, fn m -> m.ocr_status == :pending end)
        {all, pending}
      else
        {[], false}
      end

    {:ok,
     assign(socket,
       page_title: course.name,
       course: course,
       question_count: question_count,
       upcoming_tests: upcoming,
       past_tests: past,
       show_chapters: false,
       # Chapter/section editing state (kept for chapter management)
       chapter_form: nil,
       section_form: nil,
       editing_chapter: nil,
       editing_section: nil,
       expanded_chapters: MapSet.new(),
       # Discovered content sources
       discovered_sources: discovered_sources,
       show_sources: false,
       # Real-time sub-step progress (Claude Code-style)
       processing_sub_step: nil,
       # Upload state — auto-show when there are pending materials
       show_upload: has_pending,
       upload_batch_id: Ecto.UUID.generate(),
       uploaded_materials: materials,
       upload_progress: %{completed: 0, failed: 0, total: 0, in_flight: 0}
     )}
  end

  defp load_test_schedules(nil, _course_id), do: {[], []}

  defp load_test_schedules(user_role_id, course_id) do
    all = Assessments.list_test_schedules_for_course(user_role_id, course_id)
    today = Date.utc_today()

    {upcoming, past} =
      Enum.split_with(all, fn ts -> Date.compare(ts.test_date, today) != :lt end)

    # Enrich with readiness scores
    upcoming =
      Enum.map(upcoming, fn ts ->
        readiness = Assessments.latest_readiness(user_role_id, ts.id)
        %{schedule: ts, readiness: readiness}
      end)

    past =
      past
      |> Enum.sort_by(& &1.test_date, {:desc, Date})
      |> Enum.take(5)
      |> Enum.map(fn ts ->
        readiness = Assessments.latest_readiness(user_role_id, ts.id)
        %{schedule: ts, readiness: readiness}
      end)

    {upcoming, past}
  end

  @impl true
  def handle_info({:processing_update, %{sub_step: sub_step} = update}, socket)
      when is_binary(sub_step) do
    # Sub-step updates are lightweight — just update the text, don't reload everything
    socket = assign(socket, processing_sub_step: sub_step)

    # Only do a full reload if there's also a status/step change
    socket =
      if Map.has_key?(update, :status) or Map.has_key?(update, :step) do
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)
        discovered_sources = Content.list_discovered_sources(course.id)
        question_count = Questions.count_questions_by_course(course.id)
        assign(socket, course: course, discovered_sources: discovered_sources, question_count: question_count)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:processing_update, _update}, socket) do
    course = Courses.get_course_with_chapters!(socket.assigns.course.id)
    discovered_sources = Content.list_discovered_sources(course.id)
    question_count = Questions.count_questions_by_course(course.id)
    # Clear sub_step when a major step completes
    {:noreply, assign(socket, course: course, discovered_sources: discovered_sources, question_count: question_count, processing_sub_step: nil)}
  end

  def handle_info({:material_relevance_warning, _warning}, socket) do
    # Relevance warnings from MaterialRelevanceWorker — acknowledged but not surfaced in UI
    {:noreply, socket}
  end

  def handle_info({:questions_generated, _data}, socket) do
    course = Courses.get_course_with_chapters!(socket.assigns.course.id)
    question_count = Questions.count_questions_by_course(course.id)
    {:noreply, assign(socket, course: course, question_count: question_count)}
  end

  # ── Processing events ──────────────────────────────────────────────────

  def handle_event("cancel_processing", _params, socket) do
    Courses.cancel_processing(socket.assigns.course.id)
    course = Courses.get_course_with_chapters!(socket.assigns.course.id)
    {:noreply, assign(socket, course: course) |> put_flash(:info, "Processing stopped.")}
  end

  def handle_event("restart_processing", _params, socket) do
    course = socket.assigns.course

    %{course_id: course.id}
    |> FunSheep.Workers.ProcessCourseWorker.new()
    |> Oban.insert()

    Courses.update_course(course, %{
      processing_status: "processing",
      processing_step: "Restarting..."
    })

    course = Courses.get_course_with_chapters!(course.id)
    {:noreply, assign(socket, course: course) |> put_flash(:info, "Processing resumed!")}
  end

  def handle_event("reprocess_course", _params, socket) do
    {:ok, _course} = Courses.reprocess_course(socket.assigns.course.id)
    course = Courses.get_course_with_chapters!(socket.assigns.course.id)
    {:noreply, assign(socket, course: course) |> put_flash(:info, "Reprocessing started!")}
  end

  # ── Upload & Enrich events ─────────────────────────────────────────────

  def handle_event("toggle_upload", _params, socket) do
    {:noreply, assign(socket, show_upload: !socket.assigns.show_upload)}
  end

  def handle_event("upload_progress", params, socket) do
    progress = %{
      completed: params["completed"] || 0,
      failed: params["failed"] || 0,
      total: params["total"] || 0,
      in_flight: params["in_flight"] || 0
    }

    # Refresh materials list when uploads complete
    # Files are staged under batch_id (not yet linked to course), so query by batch
    socket =
      if progress.in_flight == 0 and progress.total > 0 do
        batch_materials = Content.list_materials_by_batch(socket.assigns.upload_batch_id)

        user_role_id = socket.assigns.current_user["user_role_id"]
        course_materials = Content.list_materials_by_course_for_user(socket.assigns.course.id, user_role_id)

        # Combine: course-linked materials + new batch materials (deduplicated)
        existing_ids = MapSet.new(course_materials, & &1.id)
        new_batch = Enum.reject(batch_materials, fn m -> MapSet.member?(existing_ids, m.id) end)
        assign(socket, uploaded_materials: course_materials ++ new_batch)
      else
        socket
      end

    {:noreply, assign(socket, upload_progress: progress)}
  end

  def handle_event("folder_metadata", _params, socket) do
    # Folder structure info from JS — acknowledged but not needed server-side
    {:noreply, socket}
  end

  def handle_event("enrich_course", _params, socket) do
    course = socket.assigns.course
    user_role_id = socket.assigns.current_user["user_role_id"]

    # Link current batch + any unlinked materials to this course
    Content.link_batch_to_course(socket.assigns.upload_batch_id, course.id)
    Content.link_unlinked_materials_to_course(user_role_id, course.id)

    {:ok, _} = Courses.enrich_course(course.id)
    course = Courses.get_course_with_chapters!(course.id)

    {:noreply,
     socket
     |> assign(
       course: course,
       show_upload: false,
       upload_batch_id: Ecto.UUID.generate(),
       upload_progress: %{completed: 0, failed: 0, total: 0, in_flight: 0}
     )
     |> put_flash(:info, "Processing uploaded materials...")}
  end

  def handle_event("delete_material", %{"id" => material_id}, socket) do
    material = Content.get_uploaded_material!(material_id)
    {:ok, _} = Content.delete_uploaded_material(material)

    user_role_id = socket.assigns.current_user["user_role_id"]
    materials = Content.list_materials_by_course_for_user(socket.assigns.course.id, user_role_id)
    {:noreply, assign(socket, uploaded_materials: materials)}
  end

  # ── Chapter management toggle ──────────────────────────────────────────

  def handle_event("toggle_chapters", _params, socket) do
    {:noreply, assign(socket, show_chapters: !socket.assigns.show_chapters)}
  end

  @impl true
  def handle_event("toggle_sources", _params, socket) do
    {:noreply, assign(socket, show_sources: !socket.assigns.show_sources)}
  end

  def handle_event("retry_failed_sources", _params, socket) do
    course_id = socket.assigns.course.id
    reset_count = Content.reset_failed_sources(course_id)

    if reset_count > 0 do
      # Re-run the scraper to process the reset sources
      FunSheep.Workers.WebQuestionScraperWorker.enqueue(course_id)
    end

    # Refresh sources list
    discovered_sources = Content.list_discovered_sources(course_id)

    {:noreply,
     socket
     |> assign(discovered_sources: discovered_sources)
     |> put_flash(:info, "Retrying #{reset_count} failed sources...")}
  end

  def handle_event("process_remaining_sources", _params, socket) do
    course_id = socket.assigns.course.id

    # Re-run the scraper — it picks up sources with status "discovered"
    FunSheep.Workers.WebQuestionScraperWorker.enqueue(course_id)

    {:noreply,
     socket
     |> put_flash(:info, "Processing remaining sources...")}
  end

  @impl true
  def handle_event("toggle_chapter", %{"id" => chapter_id}, socket) do
    expanded = socket.assigns.expanded_chapters

    expanded =
      if MapSet.member?(expanded, chapter_id),
        do: MapSet.delete(expanded, chapter_id),
        else: MapSet.put(expanded, chapter_id)

    {:noreply, assign(socket, expanded_chapters: expanded)}
  end

  # ── Chapter CRUD events ────────────────────────────────────────────────

  def handle_event("show_add_chapter", _params, socket) do
    {:noreply, assign(socket, chapter_form: to_form(Courses.change_chapter(%Chapter{})))}
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
         socket |> assign(course: course, chapter_form: nil) |> put_flash(:info, "Chapter added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, chapter_form: to_form(changeset))}
    end
  end

  def handle_event("edit_chapter", %{"id" => chapter_id}, socket) do
    chapter = Courses.get_chapter!(chapter_id)

    {:noreply,
     assign(socket,
       editing_chapter: chapter_id,
       chapter_form: to_form(Courses.change_chapter(chapter))
     )}
  end

  def handle_event("update_chapter", %{"chapter" => chapter_params}, socket) do
    chapter = Courses.get_chapter!(socket.assigns.editing_chapter)

    case Courses.update_chapter(chapter, chapter_params) do
      {:ok, _} ->
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

  def handle_event("move_chapter_up", %{"id" => id}, socket), do: reorder_chapter(socket, id, :up)

  def handle_event("move_chapter_down", %{"id" => id}, socket),
    do: reorder_chapter(socket, id, :down)

  # ── Section CRUD events ────────────────────────────────────────────────

  def handle_event("show_add_section", %{"chapter-id" => chapter_id}, socket) do
    {:noreply,
     assign(socket,
       section_form: to_form(Courses.change_section(%Section{})),
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

    attrs = section_params |> Map.put("chapter_id", chapter_id) |> Map.put("position", position)

    case Courses.create_section(attrs) do
      {:ok, _} ->
        course = Courses.get_course_with_chapters!(socket.assigns.course.id)

        {:noreply,
         socket |> assign(course: course, section_form: nil) |> put_flash(:info, "Section added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, section_form: to_form(changeset))}
    end
  end

  def handle_event("edit_section", %{"id" => section_id}, socket) do
    section = Courses.get_section!(section_id)

    {:noreply,
     assign(socket,
       editing_section: section_id,
       section_form: to_form(Courses.change_section(section))
     )}
  end

  def handle_event("update_section", %{"section" => section_params}, socket) do
    section = Courses.get_section!(socket.assigns.editing_section)

    case Courses.update_section(section, section_params) do
      {:ok, _} ->
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

  def handle_event("share_completed", %{"method" => method}, socket) do
    message = if method == "clipboard", do: "Link copied to clipboard!", else: "Shared!"
    {:noreply, put_flash(socket, :info, message)}
  end

  # ── Private helpers ────────────────────────────────────────────────────

  defp share_test_text(schedule, course, score) do
    base = "I'm preparing for #{schedule.name} (#{course.subject}) on Fun Sheep!"

    if score && score > 0 do
      "#{base} Currently #{score}% ready."
    else
      base
    end
  end

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

  defp days_until(date) do
    Date.diff(date, Date.utc_today())
  end

  defp urgency_color(days) when days <= 2, do: "red"
  defp urgency_color(days) when days <= 7, do: "amber"
  defp urgency_color(_days), do: "green"

  defp readiness_color(nil), do: "gray"
  defp readiness_color(score) when score >= 70, do: "green"
  defp readiness_color(score) when score >= 40, do: "amber"
  defp readiness_color(_score), do: "red"

  defp readiness_label(nil), do: "Not assessed"
  defp readiness_label(score) when score >= 70, do: "Ready"
  defp readiness_label(score) when score >= 40, do: "Almost ready"
  defp readiness_label(_score), do: "Needs work"

  defp readiness_score(nil), do: nil
  defp readiness_score(%{aggregate_score: score}), do: round(score)

  defp scope_summary(schedule, chapters) do
    scope = schedule.scope || %{}
    chapter_ids = scope["chapter_ids"] || []

    if chapter_ids == [] do
      "All chapters"
    else
      matched =
        chapters
        |> Enum.filter(&(&1.id in chapter_ids))
        |> Enum.map(& &1.name)

      case length(matched) do
        0 -> "All chapters"
        1 -> hd(matched)
        n when n <= 3 -> Enum.join(matched, ", ")
        n -> "#{hd(matched)} + #{n - 1} more"
      end
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────

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

      <%!-- Course Header --%>
      <div class="bg-white rounded-2xl shadow-md p-4 sm:p-6 mb-6">
        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3 sm:gap-4">
          <div class="min-w-0">
            <h1 class="text-xl sm:text-2xl font-bold text-[#1C1C1E]">{@course.name}</h1>
            <div class="flex gap-2 sm:gap-3 mt-2 flex-wrap">
              <span class="inline-flex items-center px-2.5 sm:px-3 py-0.5 sm:py-1 rounded-full text-[10px] sm:text-xs font-medium bg-[#E8F8EB] text-[#3DBF55]">
                {@course.subject}
              </span>
              <span class="inline-flex items-center px-2.5 sm:px-3 py-0.5 sm:py-1 rounded-full text-[10px] sm:text-xs font-medium bg-blue-50 text-blue-600">
                Grade {@course.grade}
              </span>
              <span
                :if={@course.school}
                class="inline-flex items-center px-2.5 sm:px-3 py-0.5 sm:py-1 rounded-full text-[10px] sm:text-xs font-medium bg-gray-100 text-gray-600"
              >
                <.icon name="hero-building-library" class="w-3 h-3 mr-1" /> {@course.school.name}
              </span>
            </div>
            <p :if={@course.description} class="text-sm text-[#8E8E93] mt-3">{@course.description}</p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <.share_button
              title={"#{@course.name} - Fun Sheep"}
              text={"I'm studying #{@course.subject} (Grade #{@course.grade}) on Fun Sheep! Join me."}
              url={share_url(~p"/courses/#{@course.id}")}
              style={:icon}
            />
            <button
              phx-click="toggle_upload"
              class={[
                "p-2.5 rounded-full border shadow-sm transition-colors touch-target",
                if(@show_upload,
                  do: "bg-blue-50 text-[#007AFF] border-blue-300 hover:bg-blue-100",
                  else: "bg-white hover:bg-gray-50 text-gray-500 hover:text-gray-700 border-gray-200"
                )
              ]}
              title={if(@show_upload, do: "Hide upload panel", else: "Upload textbook pages")}
            >
              <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
            </button>
            <button
              phx-click="toggle_chapters"
              class={[
                "p-2.5 rounded-full border shadow-sm transition-colors touch-target",
                if(@show_chapters,
                  do: "bg-[#E8F8EB] text-[#3DBF55] border-[#4CD964] hover:bg-[#d6f5dc]",
                  else: "bg-white hover:bg-gray-50 text-gray-500 hover:text-gray-700 border-gray-200"
                )
              ]}
              title={if(@show_chapters, do: "Hide chapter management", else: "Manage chapters")}
            >
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
            </button>
            <.link
              navigate={~p"/courses/#{@course.id}/questions"}
              class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-4 py-2.5 sm:py-2 rounded-full border border-gray-200 shadow-sm transition-colors text-sm whitespace-nowrap touch-target"
            >
              Question Bank
            </.link>
          </div>
        </div>
      </div>

      <%!-- ═══ UPLOAD MATERIALS PANEL ═══ --%>
      <.upload_panel
        :if={@show_upload}
        batch_id={@upload_batch_id}
        user_role_id={@current_user && @current_user["user_role_id"]}
        materials={@uploaded_materials}
        progress={@upload_progress}
        course={@course}
      />

      <%!-- Processing Status --%>
      <.failed_banner
        :if={@course.processing_status == "failed"}
        course={@course}
      />
      <.processing_progress
        :if={
          @course.processing_status &&
            @course.processing_status not in ["ready", "cancelled", "failed"]
        }
        course={@course}
        discovered_sources={@discovered_sources}
        question_count={@question_count}
        sub_step={@processing_sub_step}
      />
      <.cancelled_banner :if={@course.processing_status == "cancelled"} />
      <.ready_banner
        :if={
          @course.processing_status == "ready" && @course.processing_step &&
            @course.processing_step != ""
        }
        step={@course.processing_step}
        course={@course}
      />

      <%!-- ═══ DISCOVERED SOURCES (only when processing complete) ═══ --%>
      <.discovered_sources_section
        :if={@discovered_sources != [] && @course.processing_status in ["ready", nil]}
        sources={@discovered_sources}
        show_sources={@show_sources}
      />

      <%!-- ═══ UPCOMING TESTS (Hero Section) ═══ --%>
      <div class="mb-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-[#1C1C1E]">Upcoming Tests</h2>
          <.link
            navigate={~p"/courses/#{@course.id}/tests/new"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Schedule Test
          </.link>
        </div>

        <%= if @upcoming_tests == [] do %>
          <div class="bg-white rounded-2xl shadow-md p-8 text-center">
            <.icon name="hero-calendar" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
            <p class="text-[#1C1C1E] font-medium mb-1">No upcoming tests</p>
            <p class="text-sm text-[#8E8E93] mb-4">Schedule your next test to start preparing</p>
            <.link
              navigate={~p"/courses/#{@course.id}/tests/new"}
              class="inline-flex items-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors text-sm"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Schedule your first test
            </.link>
          </div>
        <% else %>
          <div class="space-y-4">
            <.test_card
              :for={test <- @upcoming_tests}
              test={test}
              course={@course}
              type={:upcoming}
            />
          </div>
        <% end %>
      </div>

      <%!-- ═══ QUICK ACTIONS ═══ --%>
      <div class="mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Practice</h2>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.link
            navigate={~p"/courses/#{@course.id}/quick-test"}
            class="bg-white rounded-2xl shadow-md p-5 flex items-center gap-4 hover:shadow-lg transition-shadow group"
          >
            <div class="w-10 h-10 bg-amber-50 rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <.icon name="hero-bolt" class="w-5 h-5 text-amber-500" />
            </div>
            <div>
              <p class="font-semibold text-[#1C1C1E]">Quick Practice</p>
              <p class="text-xs text-[#8E8E93]">Flashcard-based review</p>
            </div>
          </.link>

          <.link
            navigate={~p"/courses/#{@course.id}/study-guides"}
            class="bg-white rounded-2xl shadow-md p-5 flex items-center gap-4 hover:shadow-lg transition-shadow group"
          >
            <div class="w-10 h-10 bg-blue-50 rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <.icon name="hero-book-open" class="w-5 h-5 text-blue-500" />
            </div>
            <div>
              <p class="font-semibold text-[#1C1C1E]">Study Guides</p>
              <p class="text-xs text-[#8E8E93]">AI-powered review material</p>
            </div>
          </.link>

          <.link
            navigate={~p"/courses/#{@course.id}/tests"}
            class="bg-white rounded-2xl shadow-md p-5 flex items-center gap-4 hover:shadow-lg transition-shadow group"
          >
            <div class="w-10 h-10 bg-purple-50 rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <.icon name="hero-chart-bar" class="w-5 h-5 text-purple-500" />
            </div>
            <div>
              <p class="font-semibold text-[#1C1C1E]">All Tests</p>
              <p class="text-xs text-[#8E8E93]">History & results</p>
            </div>
          </.link>
        </div>
      </div>

      <%!-- ═══ PAST TESTS ═══ --%>
      <div :if={@past_tests != []} class="mb-6">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4">Recent Tests</h2>
        <div class="bg-white rounded-2xl shadow-md overflow-hidden">
          <div
            :for={test <- @past_tests}
            class="flex items-center justify-between px-5 py-3 border-b border-[#E5E5EA] last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <.icon name="hero-check-circle" class="w-5 h-5 text-[#4CD964] shrink-0" />
              <div>
                <p class="text-sm font-medium text-[#1C1C1E]">{test.schedule.name}</p>
                <p class="text-xs text-[#8E8E93]">
                  {Calendar.strftime(test.schedule.test_date, "%b %d, %Y")}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-4">
              <span
                :if={readiness_score(test.readiness)}
                class={"text-sm font-bold text-#{readiness_color(readiness_score(test.readiness))}-600"}
              >
                {readiness_score(test.readiness)}%
              </span>
              <.link
                navigate={~p"/courses/#{@course.id}/tests/#{test.schedule.id}/readiness"}
                class="text-xs text-[#007AFF] hover:underline"
              >
                Review
              </.link>
            </div>
          </div>
        </div>
      </div>

      <%!-- ═══ CHAPTER MANAGEMENT (Hidden by default, toggled via gear icon) ═══ --%>
      <div :if={@show_chapters} id="chapter-management" phx-hook="ScrollIntoView" class="mb-6">
        <.chapter_management
          course={@course}
          chapter_form={@chapter_form}
          section_form={@section_form}
          editing_chapter={@editing_chapter}
          editing_section={@editing_section}
          expanded_chapters={@expanded_chapters}
          section_chapter_id={assigns[:section_chapter_id]}
        />
      </div>
    </div>
    """
  end

  # ── Test Card Component ────────────────────────────────────────────────

  attr :test, :map, required: true
  attr :course, :map, required: true
  attr :type, :atom, default: :upcoming

  defp test_card(assigns) do
    days = days_until(assigns.test.schedule.test_date)
    color = urgency_color(days)
    score = readiness_score(assigns.test.readiness)
    r_color = readiness_color(score)
    r_label = readiness_label(score)
    scope_text = scope_summary(assigns.test.schedule, assigns.course.chapters)

    assigns =
      assigns
      |> assign(
        days: days,
        color: color,
        score: score,
        r_color: r_color,
        r_label: r_label,
        scope_text: scope_text
      )

    ~H"""
    <div class="bg-white rounded-2xl shadow-md overflow-hidden">
      <div class="flex">
        <%!-- Urgency bar --%>
        <div class={"w-1.5 shrink-0 bg-#{@color}-400"} />

        <div class="flex-1 p-5">
          <div class="flex items-start justify-between mb-3">
            <%!-- Test info --%>
            <div class="flex-1">
              <h3 class="font-semibold text-[#1C1C1E] text-base">{@test.schedule.name}</h3>
              <p class="text-sm text-[#8E8E93] mt-0.5">
                {@scope_text} &middot; {Calendar.strftime(@test.schedule.test_date, "%b %d, %Y")}
              </p>
            </div>

            <%!-- Days + readiness --%>
            <div class="text-right ml-4">
              <div class={"text-2xl font-bold text-#{@color}-600"}>
                {if @days == 0, do: "Today", else: @days}
              </div>
              <div :if={@days > 0} class={"text-xs text-#{@color}-500 font-medium"}>
                {if @days == 1, do: "day left", else: "days left"}
              </div>
              <div class="mt-1">
                <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-#{@r_color}-50 text-#{@r_color}-600"}>
                  {if @score, do: "#{@score}% — #{@r_label}", else: @r_label}
                </span>
              </div>
            </div>
          </div>

          <%!-- Readiness progress bar --%>
          <div class="w-full bg-gray-100 rounded-full h-2 mb-4">
            <div
              class={"bg-#{@r_color}-400 h-2 rounded-full transition-all"}
              style={"width: #{@score || 0}%"}
            />
          </div>

          <%!-- Actions --%>
          <div class="flex items-center gap-2 sm:gap-3 flex-wrap">
            <.link
              navigate={~p"/courses/#{@course.id}/tests/#{@test.schedule.id}/readiness"}
              class="text-sm font-medium text-[#007AFF] hover:text-blue-700 px-3 py-1.5 rounded-full border border-blue-200 hover:bg-blue-50 transition-colors"
            >
              <.icon name="hero-chart-bar" class="w-4 h-4 inline mr-1" /> Study Weak Areas
            </.link>
            <.link
              navigate={~p"/courses/#{@course.id}/quick-test"}
              class="text-sm font-medium text-[#8E8E93] hover:text-[#1C1C1E] px-3 py-1.5 rounded-full border border-gray-200 hover:bg-gray-50 transition-colors hidden sm:inline-flex"
            >
              <.icon name="hero-bolt" class="w-4 h-4 inline mr-1" /> Quick Practice
            </.link>
            <.share_button
              title={"#{@test.schedule.name} - #{@course.name}"}
              text={share_test_text(@test.schedule, @course, @score)}
              url={share_url(~p"/courses/#{@course.id}/tests/#{@test.schedule.id}/readiness")}
              style={:compact}
            />
            <.link
              navigate={~p"/courses/#{@course.id}/tests/#{@test.schedule.id}/assess"}
              class="ml-auto bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-4 py-1.5 rounded-full shadow-sm transition-colors text-sm"
            >
              <.icon name="hero-play" class="w-4 h-4 inline mr-1" /> Start Assessment
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Processing Status Banner Components ────────────────────────────────

  # ── Upload Panel Component ──────────────────────────────────────────────

  attr :batch_id, :string, required: true
  attr :user_role_id, :string, required: true
  attr :materials, :list, default: []
  attr :progress, :map, required: true
  attr :course, :map, required: true

  defp upload_panel(assigns) do
    pending_materials = Enum.filter(assigns.materials, fn m -> m.ocr_status == :pending end)
    has_pending = pending_materials != []
    uploading = assigns.progress.total > 0 and assigns.progress.in_flight > 0

    assigns =
      assign(assigns,
        pending_count: length(pending_materials),
        has_pending: has_pending,
        uploading: uploading
      )

    ~H"""
    <div
      id="upload-panel"
      phx-hook="DirectUploader"
      data-batch-id={@batch_id}
      data-user-role-id={@user_role_id}
      class="bg-white rounded-2xl shadow-md p-6 mb-6"
    >
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-lg font-semibold text-[#1C1C1E]">Upload Textbook Pages</h2>
          <p class="text-sm text-[#8E8E93] mt-0.5">
            Upload scanned pages or photos of your textbook to improve course content
          </p>
        </div>
      </div>

      <%!-- Upload buttons --%>
      <div class="flex flex-col sm:flex-row gap-3 mb-4">
        <button
          id="file-picker-btn"
          phx-hook="FilePicker"
          class="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-[#F5F5F7] hover:bg-[#EBEBED] text-[#1C1C1E] rounded-2xl border-2 border-dashed border-[#E5E5EA] hover:border-[#007AFF] transition-colors cursor-pointer"
        >
          <.icon name="hero-document-plus" class="w-5 h-5 text-[#007AFF]" />
          <span class="text-sm font-medium">Select Files</span>
        </button>
        <button
          id="folder-picker-btn"
          phx-hook="FolderPicker"
          class="flex-1 flex items-center justify-center gap-2 px-4 py-3 bg-[#F5F5F7] hover:bg-[#EBEBED] text-[#1C1C1E] rounded-2xl border-2 border-dashed border-[#E5E5EA] hover:border-[#007AFF] transition-colors cursor-pointer"
        >
          <.icon name="hero-folder-plus" class="w-5 h-5 text-[#007AFF]" />
          <span class="text-sm font-medium">Select Folder</span>
        </button>
      </div>

      <%!-- Upload progress --%>
      <div :if={@progress.total > 0} class="mb-4">
        <div class="flex items-center justify-between text-sm mb-1.5">
          <span class="text-[#8E8E93]">
            <%= if @uploading do %>
              Uploading {@progress.completed + @progress.in_flight}/{@progress.total} files...
            <% else %>
              {@progress.completed}/{@progress.total} files uploaded
              <%= if @progress.failed > 0 do %>
                <span class="text-[#FF3B30]">({@progress.failed} failed)</span>
              <% end %>
            <% end %>
          </span>
        </div>
        <div class="w-full bg-[#F5F5F7] rounded-full h-2">
          <div
            class="bg-[#4CD964] h-2 rounded-full transition-all duration-500"
            style={"width: #{if @progress.total > 0, do: round(@progress.completed / @progress.total * 100), else: 0}%"}
          />
        </div>
      </div>

      <%!-- Uploaded files list --%>
      <div :if={@materials != []} class="mb-4">
        <h3 class="text-sm font-medium text-[#1C1C1E] mb-2">
          Uploaded Materials ({length(@materials)})
        </h3>
        <div class="max-h-48 overflow-y-auto space-y-1.5">
          <div
            :for={mat <- @materials}
            class="flex items-center justify-between px-3 py-2 bg-[#F5F5F7] rounded-xl text-sm"
          >
            <div class="flex items-center gap-2 min-w-0">
              <.icon name={file_type_icon(mat.file_type)} class="w-4 h-4 text-[#8E8E93] shrink-0" />
              <span class="text-[#1C1C1E] truncate">{mat.file_name}</span>
              <span :if={mat.folder_name} class="text-[10px] text-[#8E8E93] px-1.5 py-0.5 bg-white rounded-full shrink-0">
                {mat.folder_name}
              </span>
            </div>
            <div class="flex items-center gap-2 shrink-0 ml-2">
              <span class={[
                "text-[10px] px-2 py-0.5 rounded-full font-medium",
                ocr_status_class(mat.ocr_status)
              ]}>
                {ocr_status_label(mat.ocr_status)}
              </span>
              <button
                :if={mat.ocr_status == :pending}
                phx-click="delete_material"
                phx-value-id={mat.id}
                class="text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
                title="Remove"
              >
                <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Process button --%>
      <div :if={@has_pending && !@uploading} class="flex items-center justify-between pt-3 border-t border-[#F5F5F7]">
        <p class="text-xs text-[#8E8E93]">
          <span class="font-medium text-[#1C1C1E]">{@pending_count} new file(s)</span>
          ready to process — this will update chapters, sections, and questions from your textbook
        </p>
        <button
          phx-click="enrich_course"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-md transition-colors text-sm whitespace-nowrap ml-3"
        >
          <.icon name="hero-sparkles" class="w-4 h-4 inline mr-1" /> Process Materials
        </button>
      </div>

      <%!-- Helpful info --%>
      <div :if={@materials == [] && @progress.total == 0} class="pt-3 border-t border-[#F5F5F7]">
        <div class="flex items-start gap-2.5">
          <.icon name="hero-light-bulb" class="w-4 h-4 text-[#FFCC00] shrink-0 mt-0.5" />
          <p class="text-xs text-[#8E8E93]">
            <span class="font-medium text-[#1C1C1E]">Supported formats:</span>
            PDF, JPG, PNG, DOC, DOCX, PPT, TXT.
            Upload your textbook's table of contents and chapter pages for the best results.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp file_type_icon(type) when is_binary(type) do
    cond do
      String.contains?(type, "pdf") -> "hero-document-text"
      String.contains?(type, "image") -> "hero-photo"
      String.contains?(type, "word") or String.contains?(type, "doc") -> "hero-document"
      String.contains?(type, "presentation") or String.contains?(type, "ppt") -> "hero-presentation-chart-bar"
      true -> "hero-document"
    end
  end

  defp file_type_icon(_), do: "hero-document"

  defp ocr_status_class(:pending), do: "bg-[#F5F5F7] text-[#8E8E93]"
  defp ocr_status_class(:processing), do: "bg-blue-50 text-[#007AFF]"
  defp ocr_status_class(:completed), do: "bg-[#E8F8EB] text-[#4CD964]"
  defp ocr_status_class(:failed), do: "bg-red-50 text-[#FF3B30]"
  defp ocr_status_class(_), do: "bg-[#F5F5F7] text-[#8E8E93]"

  defp ocr_status_label(:pending), do: "Pending"
  defp ocr_status_label(:processing), do: "Processing..."
  defp ocr_status_label(:completed), do: "Done"
  defp ocr_status_label(:failed), do: "Failed"
  defp ocr_status_label(_), do: "Unknown"

  # ── Processing Status Banner Components ────────────────────────────────

  attr :course, :map, required: true
  attr :discovered_sources, :list, default: []
  attr :question_count, :integer, default: 0
  attr :sub_step, :string, default: nil

  defp processing_progress(assigns) do
    meta = assigns.course.metadata || %{}
    discovery_done = meta["discovery_complete"] == true
    ocr_done = meta["ocr_complete"] == true
    has_ocr = assigns.course.ocr_total_count > 0
    status = assigns.course.processing_status
    sources = assigns.discovered_sources || []
    sources_count = length(sources)
    chapters = assigns.course.chapters || []
    chapters_count = length(chapters)
    question_count = assigns.question_count || 0

    web_search_done = meta["web_search_complete"] == true

    # Determine step states (web search runs first, then discovery)
    step1_state =
      cond do
        web_search_done -> :done
        true -> :active
      end

    step2_state =
      cond do
        discovery_done -> :done
        web_search_done -> :active
        true -> :pending
      end

    step3_state =
      cond do
        has_ocr && ocr_done -> :done
        has_ocr -> :active
        true -> :skip
      end

    step4_state =
      cond do
        status == "ready" -> :done
        status in ["extracting", "generating"] -> :active
        true -> :pending
      end

    assigns =
      assign(assigns,
        discovery_done: discovery_done,
        has_ocr: has_ocr,
        ocr_done: ocr_done,
        sources_count: sources_count,
        chapters_count: chapters_count,
        question_count: question_count,
        step1_state: step1_state,
        step2_state: step2_state,
        step3_state: step3_state,
        step4_state: step4_state
      )

    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-6 mb-6">
      <div class="flex items-center justify-between mb-5">
        <div>
          <h2 class="text-lg font-semibold text-[#1C1C1E]">Setting up your course</h2>
          <p class="text-sm text-[#8E8E93] mt-0.5">
            We're building your study materials — this takes about a minute
          </p>
        </div>
        <button
          phx-click="cancel_processing"
          data-confirm="Stop processing this course? You can restart it later."
          class="text-xs font-medium text-[#8E8E93] hover:text-[#FF3B30] px-3 py-1.5 rounded-full border border-[#E5E5EA] hover:border-red-200 hover:bg-red-50 transition-colors shrink-0"
        >
          Cancel
        </button>
      </div>

      <%!-- Pipeline Steps --%>
      <div class="space-y-4">
        <%!-- Step 1: Searching for content (runs first) --%>
        <.pipeline_step
          state={@step1_state}
          icon="hero-globe-alt"
          title="Searching for study materials"
          subtitle={
            cond do
              @sources_count > 0 ->
                "Found #{@sources_count} sources (textbooks, question banks, practice tests)"

              @step1_state == :active ->
                "Searching textbooks, question banks, and practice tests..."

              true ->
                "Will search for relevant study materials"
            end
          }
        />

        <%!-- Step 2: Discovering course structure (uses web search results) --%>
        <.pipeline_step
          state={@step2_state}
          icon="hero-academic-cap"
          title="Discovering course structure"
          subtitle={
            cond do
              @discovery_done ->
                "Found #{@chapters_count} chapters"

              @step2_state == :active ->
                "Identifying chapters and sections..."

              true ->
                "Will use search results to build course structure"
            end
          }
        />

        <%!-- Show discovered chapters inline --%>
        <div :if={@chapters_count > 0} class="ml-10 -mt-2 mb-1">
          <div class="flex flex-wrap gap-1.5">
            <span
              :for={chapter <- @course.chapters}
              class="text-[11px] px-2.5 py-1 rounded-full bg-[#E8F8EB] text-[#3DBF55] font-medium"
            >
              {chapter.name}
            </span>
          </div>
        </div>

        <%!-- Step 3: OCR (only if materials uploaded) --%>
        <.pipeline_step
          :if={@has_ocr}
          state={@step3_state}
          icon="hero-document-text"
          title="Processing uploaded materials"
          subtitle={"#{min(@course.ocr_completed_count, @course.ocr_total_count)} of #{@course.ocr_total_count} files processed"}
        />

        <%!-- OCR progress bar --%>
        <div :if={@has_ocr && !@ocr_done} class="ml-10 -mt-2 mb-1">
          <div class="w-full bg-[#F5F5F7] rounded-full h-1.5">
            <div
              class="bg-[#4CD964] h-1.5 rounded-full transition-all duration-500"
              style={"width: #{if @course.ocr_total_count > 0, do: min(round(@course.ocr_completed_count / @course.ocr_total_count * 100), 100), else: 0}%"}
            />
          </div>
        </div>

        <%!-- Step 4: Generating questions --%>
        <.pipeline_step
          state={@step4_state}
          icon="hero-light-bulb"
          title="Generating practice questions"
          subtitle={
            cond do
              @question_count > 0 && @step4_state == :done -> "#{@question_count} questions ready"
              @question_count > 0 -> "#{@question_count} questions so far, generating more..."
              @step4_state == :active -> "Creating questions from discovered content..."
              true -> "Will generate questions when content is ready"
            end
          }
        />
      </div>

      <%!-- Live sub-step detail (Claude Code-style) --%>
      <div :if={@sub_step} class="mt-4 ml-10">
        <div class="flex items-center gap-2 px-3 py-2 bg-[#F5F5F7] rounded-xl">
          <div class="w-1.5 h-1.5 rounded-full bg-[#007AFF] animate-pulse shrink-0" />
          <p class="text-xs text-[#8E8E93] font-mono truncate">{@sub_step}</p>
        </div>
      </div>

      <%!-- Helpful tip at bottom --%>
      <div class="mt-5 pt-4 border-t border-[#F5F5F7]">
        <div class="flex items-start gap-2.5">
          <.icon name="hero-light-bulb" class="w-4 h-4 text-[#FFCC00] shrink-0 mt-0.5" />
          <p class="text-xs text-[#8E8E93]">
            <span class="font-medium text-[#1C1C1E]">You can start using your course now!</span>
            Schedule a test or explore practice while we finish setting up. Content will appear automatically as it's ready.
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true

  defp pipeline_step(assigns) do
    ~H"""
    <div class="flex items-start gap-3">
      <%!-- Status indicator --%>
      <div class={[
        "w-7 h-7 rounded-full flex items-center justify-center shrink-0 mt-0.5",
        step_indicator_class(@state)
      ]}>
        <%= case @state do %>
          <% :done -> %>
            <.icon name="hero-check" class="w-4 h-4 text-white" />
          <% :active -> %>
            <svg
              class="w-4 h-4 text-white animate-spin"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
          <% _ -> %>
            <.icon name={@icon} class="w-3.5 h-3.5 text-[#C7C7CC]" />
        <% end %>
      </div>

      <%!-- Content --%>
      <div>
        <p class={[
          "text-sm font-medium",
          if(@state == :pending, do: "text-[#C7C7CC]", else: "text-[#1C1C1E]")
        ]}>
          {@title}
        </p>
        <p class={[
          "text-xs mt-0.5",
          if(@state == :done, do: "text-[#4CD964]", else: "text-[#8E8E93]")
        ]}>
          {@subtitle}
        </p>
      </div>
    </div>
    """
  end

  defp step_indicator_class(:done), do: "bg-[#4CD964]"
  defp step_indicator_class(:active), do: "bg-[#007AFF]"
  defp step_indicator_class(_), do: "bg-[#F5F5F7]"

  attr :course, :map, required: true

  defp failed_banner(assigns) do
    error_message =
      cond do
        assigns.course.processing_step && assigns.course.processing_step != "" ->
          assigns.course.processing_step

        assigns.course.processing_error && assigns.course.processing_error != "" ->
          assigns.course.processing_error

        true ->
          "Something went wrong while setting up your course."
      end

    assigns = assign(assigns, error_message: error_message)

    ~H"""
    <div class="bg-red-50 border border-red-200 rounded-2xl p-5 mb-6">
      <div class="flex items-start gap-3">
        <div class="w-8 h-8 rounded-full bg-[#FF3B30] flex items-center justify-center shrink-0 mt-0.5">
          <.icon name="hero-exclamation-triangle" class="w-4.5 h-4.5 text-white" />
        </div>
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-bold text-[#FF3B30] mb-1">Setup failed</h3>
          <p class="text-sm text-red-700 mb-4">{@error_message}</p>
          <div class="flex items-center gap-2">
            <button
              phx-click="restart_processing"
              class="inline-flex items-center gap-1.5 text-xs font-bold text-white bg-[#4CD964] hover:bg-[#3DBF55] px-4 py-2 rounded-full shadow-sm transition-colors"
            >
              <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Try Again
            </button>
            <button
              phx-click="reprocess_course"
              data-confirm="This will delete all existing data and start fresh. Continue?"
              class="text-xs font-medium text-[#8E8E93] hover:text-[#FF3B30] px-3 py-2 rounded-full border border-[#E5E5EA] hover:border-red-200 hover:bg-red-50 transition-colors"
            >
              Start Over
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp cancelled_banner(assigns) do
    ~H"""
    <div class="bg-amber-50 border border-amber-200 rounded-2xl p-4 mb-6">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.icon name="hero-pause-circle" class="w-5 h-5 text-amber-600 shrink-0" />
          <p class="text-sm font-medium text-amber-700">Processing was stopped.</p>
        </div>
        <div class="flex items-center gap-2">
          <button
            phx-click="restart_processing"
            class="text-xs font-bold text-purple-600 hover:text-purple-800 px-3 py-1.5 rounded-full border border-purple-200 hover:bg-purple-50 transition-colors"
          >
            Resume
          </button>
          <button
            phx-click="reprocess_course"
            data-confirm="This will delete all existing chapters, questions, and OCR data, then reprocess everything from scratch. Continue?"
            class="text-xs font-bold text-amber-600 hover:text-amber-800 px-3 py-1.5 rounded-full border border-amber-300 hover:bg-amber-50 transition-colors"
          >
            Reprocess
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :step, :string, required: true
  attr :course, :map, required: true

  defp ready_banner(assigns) do
    ~H"""
    <div class="bg-green-50 border border-green-200 rounded-2xl p-5 mb-6">
      <div class="flex items-start justify-between">
        <div class="flex items-start gap-3">
          <.icon name="hero-check-circle" class="w-5 h-5 text-green-600 shrink-0 mt-0.5" />
          <div>
            <p class="text-sm font-semibold text-green-700">Course ready!</p>
            <p class="text-xs text-green-600 mt-0.5">{@step}</p>
          </div>
        </div>
        <button
          phx-click="reprocess_course"
          data-confirm="This will delete all existing chapters, questions, and OCR data, then reprocess everything from scratch. Continue?"
          class="text-xs font-medium text-[#8E8E93] hover:text-[#FF3B30] px-3 py-1.5 rounded-full border border-[#E5E5EA] hover:border-red-200 hover:bg-red-50 transition-colors shrink-0"
        >
          Reprocess
        </button>
      </div>
      <div class="flex items-center gap-2 mt-3 ml-8">
        <.link
          navigate={~p"/courses/#{@course.id}/practice"}
          class="inline-flex items-center gap-1.5 text-xs font-bold text-white bg-[#4CD964] hover:bg-[#3DBF55] px-4 py-2 rounded-full shadow-sm transition-colors"
        >
          <.icon name="hero-bolt" class="w-3.5 h-3.5" /> Start Practicing
        </.link>
        <.link
          navigate={~p"/courses/#{@course.id}/questions"}
          class="inline-flex items-center gap-1.5 text-xs font-medium text-[#007AFF] hover:text-blue-700 px-3 py-2 rounded-full border border-blue-200 hover:bg-blue-50 transition-colors"
        >
          <.icon name="hero-rectangle-stack" class="w-3.5 h-3.5" /> View Question Bank
        </.link>
      </div>
    </div>
    """
  end

  # ── Chapter Management Component (hidden by default) ───────────────────

  attr :course, :map, required: true
  attr :chapter_form, :any, default: nil
  attr :section_form, :any, default: nil
  attr :editing_chapter, :any, default: nil
  attr :editing_section, :any, default: nil
  attr :expanded_chapters, :any, required: true
  attr :section_chapter_id, :any, default: nil

  defp chapter_management(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold text-[#1C1C1E]">Chapters & Sections</h2>
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
        <p class="text-[#8E8E93]">
          No chapters yet. Chapters are auto-discovered when the course is processed.
        </p>
      </div>

      <div
        :for={{chapter, idx} <- Enum.with_index(@course.chapters)}
        class="bg-white rounded-2xl shadow-md overflow-hidden"
      >
        <div class="flex items-center px-4 py-3 border-b border-[#E5E5EA]">
          <button
            phx-click="toggle_chapter"
            phx-value-id={chapter.id}
            class="mr-3 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
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
            <.form for={@chapter_form} phx-submit="update_chapter" class="flex-1 flex gap-3 items-end">
              <div class="flex-1"><.input field={@chapter_form[:name]} type="text" required /></div>
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
              <span class="text-xs text-[#8E8E93] ml-2">{length(chapter.sections)} section(s)</span>
            </div>
            <div class="flex items-center gap-1">
              <button
                :if={idx > 0}
                phx-click="move_chapter_up"
                phx-value-id={chapter.id}
                class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
              >
                <.icon name="hero-arrow-up" class="w-4 h-4" />
              </button>
              <button
                :if={idx < length(@course.chapters) - 1}
                phx-click="move_chapter_down"
                phx-value-id={chapter.id}
                class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
              >
                <.icon name="hero-arrow-down" class="w-4 h-4" />
              </button>
              <button
                phx-click="show_add_section"
                phx-value-chapter-id={chapter.id}
                class="p-1 text-[#4CD964] hover:text-[#3DBF55] transition-colors"
              >
                <.icon name="hero-plus" class="w-4 h-4" />
              </button>
              <button
                phx-click="edit_chapter"
                phx-value-id={chapter.id}
                class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
              >
                <.icon name="hero-pencil" class="w-4 h-4" />
              </button>
              <button
                phx-click="delete_chapter"
                phx-value-id={chapter.id}
                data-confirm="Delete this chapter and all its sections?"
                class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
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
                <div class="flex-1"><.input field={@section_form[:name]} type="text" required /></div>
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
                <.icon name="hero-document" class="w-4 h-4 inline mr-1 text-[#8E8E93]" />{section.name}
              </span>
              <div class="flex items-center gap-1">
                <button
                  phx-click="edit_section"
                  phx-value-id={section.id}
                  class="p-1 text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
                >
                  <.icon name="hero-pencil" class="w-3 h-3" />
                </button>
                <button
                  phx-click="delete_section"
                  phx-value-id={section.id}
                  data-confirm="Delete this section?"
                  class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
                >
                  <.icon name="hero-trash" class="w-3 h-3" />
                </button>
              </div>
            <% end %>
          </div>

          <div
            :if={@section_form && @editing_section == nil && @section_chapter_id == chapter.id}
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
            :if={chapter.sections == [] && !(@section_form && @section_chapter_id == chapter.id)}
            class="px-8 py-4 text-center"
          >
            <p class="text-sm text-[#8E8E93]">No sections yet</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Discovered Sources Component ──

  attr :sources, :list, required: true
  attr :show_sources, :boolean, required: true

  defp discovered_sources_section(assigns) do
    by_type = Enum.group_by(assigns.sources, & &1.source_type)
    total_questions = assigns.sources |> Enum.map(& &1.questions_extracted) |> Enum.sum()
    processed = Enum.count(assigns.sources, &(&1.status == "processed"))
    failed = Enum.count(assigns.sources, &(&1.status == "failed"))
    found = Enum.count(assigns.sources, &(&1.status == "discovered"))

    assigns =
      assign(assigns,
        by_type: by_type,
        total_questions: total_questions,
        processed_count: processed,
        failed_count: failed,
        found_count: found
      )

    ~H"""
    <div class="mb-6">
      <button
        phx-click="toggle_sources"
        class="w-full bg-white rounded-2xl shadow-md p-4 flex items-center justify-between hover:shadow-lg transition-shadow"
      >
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 bg-blue-50 rounded-xl flex items-center justify-center">
            <.icon name="hero-globe-alt" class="w-5 h-5 text-[#007AFF]" />
          </div>
          <div class="text-left">
            <p class="font-semibold text-[#1C1C1E] text-sm">
              {length(@sources)} Content Sources Found
            </p>
            <p class="text-xs text-[#8E8E93]">
              {source_summary_text(@by_type)}
              <%= if @total_questions > 0 do %>
                · {@total_questions} questions extracted
              <% end %>
            </p>
          </div>
        </div>
        <.icon
          name={if @show_sources, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="w-5 h-5 text-[#8E8E93]"
        />
      </button>

      <div :if={@show_sources} class="mt-3 space-y-3">
        <%!-- Action bar for failed/remaining sources --%>
        <div :if={@failed_count > 0 || @found_count > 0} class="flex items-center gap-2 px-1">
          <button
            :if={@failed_count > 0}
            phx-click="retry_failed_sources"
            class="inline-flex items-center gap-1.5 text-xs font-medium text-[#FF3B30] hover:text-red-700 px-3 py-1.5 rounded-full border border-red-200 hover:bg-red-50 transition-colors"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
            Retry {@failed_count} failed
          </button>
          <button
            :if={@found_count > 0}
            phx-click="process_remaining_sources"
            class="inline-flex items-center gap-1.5 text-xs font-medium text-[#007AFF] hover:text-blue-700 px-3 py-1.5 rounded-full border border-blue-200 hover:bg-blue-50 transition-colors"
          >
            <.icon name="hero-play" class="w-3.5 h-3.5" />
            Process {@found_count} remaining
          </button>
          <span class="text-xs text-[#8E8E93] ml-auto">
            {@processed_count} done · {@failed_count} failed · {@found_count} pending
          </span>
        </div>

        <div
          :for={{type, sources} <- @by_type}
          class="bg-white rounded-2xl shadow-sm p-4"
        >
          <div class="flex items-center gap-2 mb-3">
            <.icon name={source_type_icon(type)} class="w-4 h-4 text-[#8E8E93]" />
            <h4 class="text-sm font-semibold text-[#1C1C1E] capitalize">
              {source_type_label(type)}
            </h4>
            <span class="text-xs text-[#8E8E93] bg-[#F5F5F7] px-2 py-0.5 rounded-full">
              {length(sources)}
            </span>
          </div>

          <div class="space-y-2">
            <div
              :for={source <- sources}
              class="flex items-start justify-between gap-2 p-2 rounded-xl hover:bg-[#F5F5F7] transition-colors"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-[#1C1C1E] truncate">{source.title}</p>
                <p :if={source.publisher} class="text-xs text-[#8E8E93]">
                  {source.publisher}
                </p>
                <p :if={source.description} class="text-xs text-[#8E8E93] mt-0.5 line-clamp-2">
                  {source.description}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <span :if={source.questions_extracted > 0} class="text-xs text-[#4CD964] font-medium">
                  {source.questions_extracted} Q
                </span>
                <span class={[
                  "text-[10px] px-2 py-0.5 rounded-full font-medium",
                  source_status_class(source.status)
                ]}>
                  {source_status_label(source.status)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp source_summary_text(by_type) do
    parts =
      by_type
      |> Enum.map(fn {type, sources} ->
        "#{length(sources)} #{source_type_label(type)}"
      end)

    Enum.join(parts, ", ")
  end

  defp source_type_icon("textbook"), do: "hero-book-open"
  defp source_type_icon("question_bank"), do: "hero-question-mark-circle"
  defp source_type_icon("practice_test"), do: "hero-clipboard-document-check"
  defp source_type_icon("study_guide"), do: "hero-document-text"
  defp source_type_icon("curriculum"), do: "hero-academic-cap"
  defp source_type_icon("video"), do: "hero-play-circle"
  defp source_type_icon(_), do: "hero-document"

  defp source_type_label("textbook"), do: "textbooks"
  defp source_type_label("question_bank"), do: "question banks"
  defp source_type_label("practice_test"), do: "practice tests"
  defp source_type_label("study_guide"), do: "study guides"
  defp source_type_label("curriculum"), do: "curricula"
  defp source_type_label("video"), do: "videos"
  defp source_type_label(_), do: "sources"

  defp source_status_class("processed"), do: "bg-[#E8F8EB] text-[#4CD964]"
  defp source_status_class("scraped"), do: "bg-blue-50 text-[#007AFF]"
  defp source_status_class("scraping"), do: "bg-yellow-50 text-yellow-600"
  defp source_status_class("discovered"), do: "bg-[#F5F5F7] text-[#8E8E93]"
  defp source_status_class("failed"), do: "bg-red-50 text-[#FF3B30]"
  defp source_status_class("skipped"), do: "bg-[#F5F5F7] text-[#C7C7CC]"
  defp source_status_class(_), do: "bg-[#F5F5F7] text-[#8E8E93]"

  defp source_status_label("processed"), do: "Done"
  defp source_status_label("scraped"), do: "Scraped"
  defp source_status_label("scraping"), do: "Loading..."
  defp source_status_label("discovered"), do: "Found"
  defp source_status_label("failed"), do: "Failed"
  defp source_status_label("skipped"), do: "Skipped"
  defp source_status_label(status), do: status
end
