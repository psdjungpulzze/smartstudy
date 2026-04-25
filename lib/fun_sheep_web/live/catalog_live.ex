defmodule FunSheepWeb.CatalogLive do
  @moduledoc """
  Premium catalog browsing page.

  Lists all published premium catalog courses. Users can filter by category
  (test type). Locked courses show an upgrade interstitial via the
  UpgradeModalComponent. Accessible courses show a "Start Practicing" CTA.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.{Courses, Billing}

  @categories [
    {"All", nil},
    {"College Admission", ["sat", "act", "clt"]},
    {"AP Courses", ["ap"]},
    {"International", ["ib", "hsc"]},
    {"Professional", ["lsat", "bar", "gmat", "mcat", "gre"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_role_id = user["user_role_id"] || user["id"]

    all_courses = Courses.list_premium_catalog()

    subscription = Billing.get_subscription(user_role_id)

    access_map =
      Map.new(all_courses, fn course ->
        accessible = Billing.subscription_grants_access?(subscription, course)
        {course.id, accessible}
      end)

    {:ok,
     assign(socket,
       page_title: "Course Catalog",
       all_courses: all_courses,
       filtered_courses: all_courses,
       access_map: access_map,
       subscription: subscription,
       selected_category: nil,
       categories: @categories,
       upgrade_course: nil
     )}
  end

  @impl true
  def handle_params(%{"category" => cat}, _url, socket) do
    {:noreply, apply_category(socket, cat)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_category(socket, nil)}
  end

  @impl true
  def handle_event("select_category", %{"category" => cat}, socket) do
    {:noreply, push_patch(socket, to: catalog_path(cat))}
  end

  def handle_event("open_upgrade", %{"course-id" => course_id}, socket) do
    course = Enum.find(socket.assigns.all_courses, &(&1.id == course_id))
    {:noreply, assign(socket, upgrade_course: course)}
  end

  def handle_event("close_upgrade_modal", _params, socket) do
    {:noreply, assign(socket, upgrade_course: nil)}
  end

  @impl true
  def handle_info({:close_upgrade_modal}, socket) do
    {:noreply, assign(socket, upgrade_course: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="animate-slide-up">
      <%!-- Hero --%>
      <div class="mb-8 text-center">
        <div class="text-5xl mb-3">🎓</div>
        <h1 class="text-2xl sm:text-3xl font-extrabold text-gray-900">
          Prep for the tests that matter most
        </h1>
        <p class="text-gray-500 text-sm mt-2 max-w-lg mx-auto">
          Expert-crafted question banks for SAT, ACT, AP, IB, and more — with AI-powered practice and explanations.
        </p>
      </div>

      <%!-- Category Tabs --%>
      <div class="flex gap-2 overflow-x-auto pb-2 mb-6 scrollbar-hide">
        <button
          :for={{label, types} <- @categories}
          phx-click="select_category"
          phx-value-category={category_key(types)}
          class={[
            "shrink-0 px-4 py-2 rounded-full text-sm font-medium transition-all border",
            if(category_selected?(@selected_category, types),
              do: "bg-[#4CD964] border-[#4CD964] text-white shadow-sm",
              else:
                "bg-white border-gray-200 text-gray-600 hover:border-[#4CD964] hover:text-[#4CD964]"
            )
          ]}
        >
          {label}
        </button>
      </div>

      <%!-- Course Grid --%>
      <div :if={@filtered_courses == []} class="text-center py-16">
        <div class="text-5xl mb-3">📭</div>
        <h2 class="font-bold text-gray-900 text-lg">No courses in this category yet</h2>
        <p class="text-gray-500 text-sm mt-1">
          Check back soon — we're adding new content regularly.
        </p>
      </div>

      <div :if={@filtered_courses != []} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <.catalog_card
          :for={{course, idx} <- Enum.with_index(@filtered_courses)}
          course={course}
          idx={idx}
          accessible={Map.get(@access_map, course.id, false)}
        />
      </div>
    </div>

    <%!-- Upgrade Modal --%>
    <.live_component
      :if={@upgrade_course}
      module={FunSheepWeb.UpgradeModalComponent}
      id="upgrade-modal"
      course={@upgrade_course}
    />
    """
  end

  # ── Catalog Card ─────────────────────────────────────────────────────────────

  attr :course, :any, required: true
  attr :idx, :integer, required: true
  attr :accessible, :boolean, required: true

  defp catalog_card(assigns) do
    ~H"""
    <div class={"bg-white rounded-2xl border border-gray-100 p-5 flex flex-col gap-3 card-hover animate-slide-up stagger-#{rem(@idx, 6) + 1}"}>
      <%!-- Badges --%>
      <div class="flex flex-wrap gap-1.5">
        <span
          :if={@course.catalog_test_type}
          class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-[#E8F8EB] text-[#4CD964]"
        >
          {String.upcase(@course.catalog_test_type || "")}
        </span>
        <span
          :if={@course.catalog_subject}
          class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
        >
          {humanize_subject(@course.catalog_subject)}
        </span>
        <span
          :if={@course.catalog_level}
          class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-50 text-blue-600"
        >
          {String.upcase(@course.catalog_level || "")}
        </span>
      </div>

      <%!-- Course name --%>
      <div class="flex-1">
        <h3 class="font-bold text-gray-900 text-sm leading-snug">{@course.name}</h3>
        <p :if={@course.description} class="text-gray-500 text-xs mt-1 line-clamp-2">
          {@course.description}
        </p>
      </div>

      <%!-- Stats row --%>
      <div class="flex items-center gap-3 text-xs text-gray-400">
        <span class="flex items-center gap-1">
          <.icon name="hero-question-mark-circle" class="w-3.5 h-3.5" />
          {sample_label(@course, @accessible)}
        </span>
        <span class="flex items-center gap-1">
          <.icon :if={!@accessible} name="hero-lock-closed" class="w-3.5 h-3.5" />
          <.icon :if={@accessible} name="hero-check-circle" class="w-3.5 h-3.5 text-[#4CD964]" />
          {access_label(@course.access_level)}
        </span>
      </div>

      <%!-- CTA --%>
      <%= if @accessible do %>
        <.link
          navigate={~p"/courses/#{@course.id}"}
          class="w-full text-center bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold px-4 py-2.5 rounded-full shadow-md btn-bounce text-sm transition-colors"
        >
          Start Practicing
        </.link>
      <% else %>
        <button
          phx-click="open_upgrade"
          phx-value-course-id={@course.id}
          class="w-full text-center bg-gray-900 hover:bg-gray-700 text-white font-bold px-4 py-2.5 rounded-full shadow-md btn-bounce text-sm transition-colors flex items-center justify-center gap-2"
        >
          <.icon name="hero-lock-closed" class="w-4 h-4" /> Unlock
        </button>
      <% end %>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp apply_category(socket, nil) do
    assign(socket,
      selected_category: nil,
      filtered_courses: socket.assigns.all_courses
    )
  end

  defp apply_category(socket, cat_key) when is_binary(cat_key) do
    matching_category =
      Enum.find(@categories, fn {_label, types} ->
        category_key(types) == cat_key
      end)

    case matching_category do
      {_label, types} when is_list(types) ->
        filtered =
          Enum.filter(socket.assigns.all_courses, fn course ->
            course.catalog_test_type in types
          end)

        assign(socket,
          selected_category: cat_key,
          filtered_courses: filtered
        )

      _ ->
        apply_category(socket, nil)
    end
  end

  defp catalog_path(nil), do: ~p"/catalog"
  defp catalog_path(""), do: ~p"/catalog"
  defp catalog_path(cat), do: ~p"/catalog?category=#{cat}"

  defp category_key(nil), do: nil
  defp category_key(types) when is_list(types), do: Enum.join(types, "-")

  defp category_selected?(nil, nil), do: true
  defp category_selected?(_selected, nil), do: false
  defp category_selected?(nil, _types), do: false

  defp category_selected?(selected, types) when is_list(types) do
    category_key(types) == selected
  end

  defp humanize_subject(nil), do: ""

  defp humanize_subject(subject) do
    subject
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp sample_label(course, true), do: "#{course.sample_question_count}+ questions"
  defp sample_label(course, false), do: "#{course.sample_question_count} free questions"

  defp access_label("public"), do: "Free"
  defp access_label("preview"), do: "Preview"
  defp access_label("standard"), do: "Standard"
  defp access_label("premium"), do: "Premium"
  defp access_label("professional"), do: "Professional"
  defp access_label(_), do: "Free"
end
