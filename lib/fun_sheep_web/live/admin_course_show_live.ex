defmodule FunSheepWeb.AdminCourseShowLive do
  @moduledoc """
  Admin detail view for a single course.

  Shows core metadata (owner, status, test type) alongside a live pipeline
  audit — source discovery counts, scraping stats, and per-domain extraction
  yield — produced by `FunSheep.Questions.pipeline_audit_for_course/1`.
  """

  use FunSheepWeb, :live_view

  import FunSheepWeb.Components.AdminSidebar

  alias FunSheep.{Courses, Questions}

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course_with_chapters!(id)
    audit = Questions.pipeline_audit_for_course(id)

    {:ok,
     socket
     |> assign(:page_title, "Course · #{course.name}")
     |> assign(:current_path, "/admin/courses")
     |> assign(:course, course)
     |> assign(:audit, audit)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-[#F5F5F7] dark:bg-[#1C1C1E]">
      <.admin_sidebar current_path={@current_path} />

      <main class="flex-1 ml-64 p-8">
        <div class="max-w-6xl mx-auto">
          <%# Header %>
          <div class="flex items-center gap-3 mb-6">
            <.link navigate="/admin/courses" class="text-[#007AFF] text-sm hover:underline">
              ← Courses
            </.link>
            <span class="text-[#8E8E93]">/</span>
            <h1 class="text-xl font-semibold text-[#1C1C1E] dark:text-white truncate">
              <%= @course.name %>
            </h1>
          </div>

          <%# Course metadata %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-6 mb-6 grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="text-[#8E8E93]">Test type</p>
              <p class="font-medium text-[#1C1C1E] dark:text-white mt-1">
                <%= @course.catalog_test_type || "—" %>
              </p>
            </div>
            <div>
              <p class="text-[#8E8E93]">Subject</p>
              <p class="font-medium text-[#1C1C1E] dark:text-white mt-1">
                <%= @course.catalog_subject || "—" %>
              </p>
            </div>
            <div>
              <p class="text-[#8E8E93]">Status</p>
              <p class="font-medium text-[#1C1C1E] dark:text-white mt-1">
                <%= @course.processing_status || "—" %>
              </p>
            </div>
            <div>
              <p class="text-[#8E8E93]">Access</p>
              <p class="font-medium text-[#1C1C1E] dark:text-white mt-1">
                <%= @course.access_level || "—" %>
              </p>
            </div>
          </div>

          <%# Pipeline audit headline stats %>
          <h2 class="text-base font-semibold text-[#1C1C1E] dark:text-white mb-3">
            Pipeline audit
          </h2>

          <div class="grid grid-cols-3 gap-4 mb-6">
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Sources discovered</p>
              <p class="text-2xl font-semibold text-[#1C1C1E] dark:text-white mt-1">
                <%= @audit.sources_discovered %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Sources scraped</p>
              <p class="text-2xl font-semibold text-[#4CD964] mt-1">
                <%= @audit.sources_scraped %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Sources failed</p>
              <p class={["text-2xl font-semibold mt-1", if(@audit.sources_failed > 0, do: "text-[#FF3B30]", else: "text-[#8E8E93]")]}>
                <%= @audit.sources_failed %>
              </p>
            </div>
          </div>

          <div class="grid grid-cols-4 gap-4 mb-6">
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Questions extracted</p>
              <p class="text-2xl font-semibold text-[#1C1C1E] dark:text-white mt-1">
                <%= @audit.questions_extracted %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Passed validation</p>
              <p class="text-2xl font-semibold text-[#4CD964] mt-1">
                <%= @audit.questions_passed %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Needs review</p>
              <p class="text-2xl font-semibold text-[#FFCC00] mt-1">
                <%= @audit.questions_needs_review %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-5">
              <p class="text-xs text-[#8E8E93] uppercase tracking-wider">Failed validation</p>
              <p class={["text-2xl font-semibold mt-1", if(@audit.questions_failed > 0, do: "text-[#FF3B30]", else: "text-[#8E8E93]")]}>
                <%= @audit.questions_failed %>
              </p>
            </div>
          </div>

          <%# Per-domain breakdown %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm overflow-hidden">
            <div class="px-6 py-4 border-b border-[#E5E5EA] dark:border-[#3A3A3C]">
              <h3 class="text-sm font-semibold text-[#1C1C1E] dark:text-white">
                Per-domain extraction
              </h3>
            </div>
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-[#E5E5EA] dark:border-[#3A3A3C]">
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Domain</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Strategy</th>
                  <th class="text-right px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Sources</th>
                  <th class="text-right px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Extracted</th>
                  <th class="text-right px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Passed</th>
                  <th class="text-right px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Pass rate</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#E5E5EA] dark:divide-[#3A3A3C]">
                <%= for row <- @audit.by_domain do %>
                  <tr class="hover:bg-[#F5F5F7] dark:hover:bg-[#3A3A3C] transition-colors">
                    <td class="px-6 py-3 font-medium text-[#1C1C1E] dark:text-white"><%= row.domain || "unknown" %></td>
                    <td class="px-6 py-3 text-[#8E8E93]">
                      <span class={["text-xs px-2 py-0.5 rounded-full", strategy_badge(row.strategy)]}>
                        <%= row.strategy %>
                      </span>
                    </td>
                    <td class="px-6 py-3 text-right text-[#8E8E93]"><%= row.sources %></td>
                    <td class="px-6 py-3 text-right text-[#1C1C1E] dark:text-white"><%= row.extracted %></td>
                    <td class="px-6 py-3 text-right text-[#4CD964]"><%= row.passed %></td>
                    <td class="px-6 py-3 text-right">
                      <span class={pass_rate_class(row.pass_rate)}>
                        <%= format_pct(row.pass_rate) %>
                      </span>
                    </td>
                  </tr>
                <% end %>
                <%= if @audit.by_domain == [] do %>
                  <tr>
                    <td colspan="6" class="px-6 py-10 text-center text-[#8E8E93] text-sm">
                      No sources discovered yet for this course.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # --- Private helpers ---

  defp strategy_badge("registry"), do: "bg-[#E8F8EB] text-[#2D6A4F]"
  defp strategy_badge("web_search"), do: "bg-blue-50 text-blue-700"
  defp strategy_badge(_), do: "bg-gray-100 text-gray-600"

  defp pass_rate_class(rate) when rate >= 0.8, do: "text-[#4CD964] font-medium"
  defp pass_rate_class(rate) when rate >= 0.5, do: "text-[#FFCC00] font-medium"
  defp pass_rate_class(_), do: "text-[#FF3B30] font-medium"

  defp format_pct(rate), do: "#{round(rate * 100)}%"
end
