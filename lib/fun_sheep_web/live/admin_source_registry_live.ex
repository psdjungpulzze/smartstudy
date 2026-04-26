defmodule FunSheepWeb.AdminSourceRegistryLive do
  use FunSheepWeb, :live_view

  import Ecto.Query
  import FunSheepWeb.Components.AdminSidebar

  alias FunSheep.{Repo}
  alias FunSheep.Discovery.SourceRegistryEntry
  alias FunSheep.Discovery.RegistrySeeder

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Source registry")
     |> assign(:current_path, "/admin/source-registry")
     |> assign(:filter_test_type, nil)
     |> assign(:verify_results, %{})
     |> assign(:seed_results, %{})
     |> load_entries()}
  end

  @impl true
  def handle_params(%{"test_type" => test_type}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:filter_test_type, test_type)
     |> load_entries(test_type)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"test_type" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:filter_test_type, nil)
     |> load_entries()}
  end

  def handle_event("filter", %{"test_type" => test_type}, socket) do
    {:noreply,
     socket
     |> assign(:filter_test_type, test_type)
     |> load_entries(test_type)}
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    entry = Repo.get!(SourceRegistryEntry, id)

    {:ok, updated} =
      entry
      |> SourceRegistryEntry.changeset(%{is_enabled: !entry.is_enabled})
      |> Repo.update()

    entries =
      Enum.map(socket.assigns.entries, fn e ->
        if e.id == updated.id, do: updated, else: e
      end)

    {:noreply, assign(socket, :entries, entries)}
  end

  def handle_event("verify", %{"id" => id}, socket) do
    entry = Repo.get!(SourceRegistryEntry, id)

    result =
      case FunSheep.Workers.SourceRegistryVerifierWorker.probe_url(entry.url_or_pattern) do
        :ok -> {:ok, "URL reachable"}
        {:error, reason} -> {:error, inspect(reason)}
      end

    {:noreply, assign(socket, :verify_results, Map.put(socket.assigns.verify_results, id, result))}
  end

  def handle_event("seed_course", %{"course_id" => course_id}, socket) do
    course = FunSheep.Courses.get_course_with_chapters!(course_id)

    case RegistrySeeder.seed_from_registry(course) do
      {:ok, count} ->
        {:noreply,
         assign(socket, :seed_results, Map.put(socket.assigns.seed_results, course_id, {:ok, count}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-[#F5F5F7] dark:bg-[#1C1C1E]">
      <.admin_sidebar current_path={@current_path} />

      <main class="flex-1 ml-64 p-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-6">
            <div>
              <h1 class="text-2xl font-semibold text-[#1C1C1E] dark:text-white">Source Registry</h1>
              <p class="text-sm text-[#8E8E93] mt-1">
                Curated sources seeded into every new course before web search runs.
              </p>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-sm text-[#8E8E93]"><%= length(@entries) %> entries</span>
            </div>
          </div>

          <%# Filter bar %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-4 mb-6">
            <form phx-change="filter" class="flex items-center gap-4">
              <label class="text-sm font-medium text-[#1C1C1E] dark:text-white">Filter by test type:</label>
              <select
                name="test_type"
                class="px-4 py-2 bg-[#F5F5F7] dark:bg-[#3A3A3C] border border-[#E5E5EA] dark:border-[#3A3A3C] rounded-full text-sm focus:border-[#4CD964] outline-none"
              >
                <option value="">All test types</option>
                <%= for test_type <- test_types(@entries) do %>
                  <option value={test_type} selected={@filter_test_type == test_type}>
                    <%= test_type %>
                  </option>
                <% end %>
              </select>
            </form>
          </div>

          <%# Entries table %>
          <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-[#E5E5EA] dark:border-[#3A3A3C]">
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Test type</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Subject</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">URL</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Tier</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Type</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Avg Q/page</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Failures</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Enabled</th>
                  <th class="text-left px-6 py-3 text-xs font-medium text-[#8E8E93] uppercase tracking-wider">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[#E5E5EA] dark:divide-[#3A3A3C]">
                <%= for entry <- @entries do %>
                  <tr class="hover:bg-[#F5F5F7] dark:hover:bg-[#3A3A3C] transition-colors">
                    <td class="px-6 py-4 font-medium text-[#1C1C1E] dark:text-white">
                      <%= entry.test_type %>
                    </td>
                    <td class="px-6 py-4 text-[#8E8E93]">
                      <%= entry.catalog_subject || "—" %>
                    </td>
                    <td class="px-6 py-4 max-w-xs">
                      <a
                        href={entry.url_or_pattern}
                        target="_blank"
                        class="text-[#007AFF] hover:underline truncate block"
                        title={entry.url_or_pattern}
                      >
                        <%= entry.domain %>
                      </a>
                      <%= if result = Map.get(@verify_results, entry.id) do %>
                        <span class={["text-xs mt-1 block", verify_class(result)]}>
                          <%= verify_label(result) %>
                        </span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4">
                      <span class={["px-2 py-1 rounded-full text-xs font-medium", tier_class(entry.tier)]}>
                        Tier <%= entry.tier %>
                      </span>
                    </td>
                    <td class="px-6 py-4 text-[#8E8E93]"><%= entry.source_type %></td>
                    <td class="px-6 py-4 text-[#8E8E93] text-center"><%= entry.avg_questions_per_page || "?" %></td>
                    <td class="px-6 py-4">
                      <span class={["text-xs font-medium", if(entry.consecutive_failures >= 3, do: "text-[#FF3B30]", else: "text-[#8E8E93]")]}>
                        <%= entry.consecutive_failures %>
                      </span>
                    </td>
                    <td class="px-6 py-4">
                      <button
                        phx-click="toggle_enabled"
                        phx-value-id={entry.id}
                        class={[
                          "relative inline-flex h-5 w-9 items-center rounded-full transition-colors",
                          if(entry.is_enabled, do: "bg-[#4CD964]", else: "bg-[#E5E5EA] dark:bg-[#3A3A3C]")
                        ]}
                      >
                        <span class={[
                          "inline-block h-3 w-3 rounded-full bg-white shadow transform transition-transform",
                          if(entry.is_enabled, do: "translate-x-5", else: "translate-x-1")
                        ]} />
                      </button>
                    </td>
                    <td class="px-6 py-4">
                      <button
                        phx-click="verify"
                        phx-value-id={entry.id}
                        class="text-xs text-[#007AFF] hover:underline"
                      >
                        Verify URL
                      </button>
                    </td>
                  </tr>
                <% end %>
                <%= if @entries == [] do %>
                  <tr>
                    <td colspan="9" class="px-6 py-12 text-center text-[#8E8E93]">
                      No entries found. Run <code class="font-mono text-xs">mix run priv/repo/seeds/source_registry.exs</code> to seed initial data.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%# Stats summary %>
          <div class="grid grid-cols-3 gap-4 mt-6">
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-6">
              <p class="text-sm text-[#8E8E93]">Total entries</p>
              <p class="text-2xl font-semibold text-[#1C1C1E] dark:text-white mt-1"><%= length(@entries) %></p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-6">
              <p class="text-sm text-[#8E8E93]">Enabled</p>
              <p class="text-2xl font-semibold text-[#4CD964] mt-1">
                <%= Enum.count(@entries, & &1.is_enabled) %>
              </p>
            </div>
            <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-sm p-6">
              <p class="text-sm text-[#8E8E93]">Disabled (failures)</p>
              <p class="text-2xl font-semibold text-[#FF3B30] mt-1">
                <%= Enum.count(@entries, &(not &1.is_enabled)) %>
              </p>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # --- Private helpers ---

  defp load_entries(socket, test_type \\ nil) do
    query = from(e in SourceRegistryEntry, order_by: [asc: e.test_type, asc: e.tier])

    query =
      if test_type,
        do: where(query, [e], e.test_type == ^test_type),
        else: query

    assign(socket, :entries, Repo.all(query))
  end

  defp test_types(entries) do
    entries |> Enum.map(& &1.test_type) |> Enum.uniq() |> Enum.sort()
  end

  defp tier_class(1), do: "bg-[#E8F8EB] text-[#2D6A4F]"
  defp tier_class(2), do: "bg-blue-50 text-blue-700"
  defp tier_class(3), do: "bg-yellow-50 text-yellow-700"
  defp tier_class(_), do: "bg-gray-100 text-gray-600"

  defp verify_class({:ok, _}), do: "text-[#4CD964]"
  defp verify_class({:error, _}), do: "text-[#FF3B30]"

  defp verify_label({:ok, msg}), do: "✓ #{msg}"
  defp verify_label({:error, reason}), do: "✗ #{reason}"
end
