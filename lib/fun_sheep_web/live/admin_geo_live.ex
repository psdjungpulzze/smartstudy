defmodule FunSheepWeb.AdminGeoLive do
  @moduledoc """
  /admin/geo — read-only browser for the geo hierarchy
  (countries → states → districts → schools) that FunSheep's ingesters
  populate.

  Schema-driven CRUD is deferred; this page focuses on the operational
  triage use case: "find the school this user/course is linked to and
  see how many students/courses it has."
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Geo, Repo}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Geo · Admin")
     |> assign(:query, "")
     |> assign(:country_filter, "")
     |> load_data()}
  end

  @impl true
  def handle_event("search", %{"query" => q} = params, socket) do
    {:noreply,
     socket
     |> assign(:query, q)
     |> assign(:country_filter, params["country_id"] || "")
     |> load_data()}
  end

  defp load_data(socket) do
    countries = Geo.list_countries()

    schools =
      Geo.search_schools(%{
        query: socket.assigns.query,
        country_id: socket.assigns.country_filter,
        limit: 50
      })

    counts = %{
      countries: length(countries),
      states: Repo.aggregate(Geo.State, :count),
      districts: Repo.aggregate(Geo.District, :count),
      schools: Repo.aggregate(Geo.School, :count)
    }

    socket
    |> assign(:countries, countries)
    |> assign(:schools, schools)
    |> assign(:counts, counts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto space-y-4">
      <div>
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Geo</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Browse the geographic hierarchy that FunSheep ingesters populate
          (NCES, GIAS, ACARA, NEIS, IB). Read-only for now — full CRUD
          lands in a later PR.
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.count_card label="Countries" count={@counts.countries} />
        <.count_card label="States / provinces" count={@counts.states} />
        <.count_card label="Districts" count={@counts.districts} />
        <.count_card label="Schools" count={@counts.schools} accent="text-[#4CD964]" />
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4">
        <form phx-change="search" class="flex items-center gap-2 flex-wrap">
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search schools by name…"
            phx-debounce="300"
            class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
          <select
            name="country_id"
            class="px-3 py-2 text-sm rounded-full bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] outline-none"
          >
            <option value="" selected={@country_filter == ""}>All countries</option>
            <option :for={c <- @countries} value={c.id} selected={@country_filter == c.id}>
              {c.name}
            </option>
          </select>
        </form>
      </div>

      <div class="bg-white rounded-2xl shadow-md overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-sm min-w-[640px]">
            <thead class="bg-[#F5F5F7] text-[#8E8E93] uppercase text-xs">
              <tr>
                <th class="text-left px-4 py-3">Name</th>
                <th class="text-left px-4 py-3">Country · State</th>
                <th class="text-left px-4 py-3">Level</th>
                <th class="text-left px-4 py-3">Type</th>
                <th class="text-right px-4 py-3">Students</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @schools} class="border-t border-[#F5F5F7]">
                <td class="px-4 py-3 font-medium text-[#1C1C1E]">
                  {s.name || s.native_name || "(unnamed)"}
                </td>
                <td class="px-4 py-3 text-[#8E8E93]">
                  {country_state(s, @countries)}
                </td>
                <td class="px-4 py-3 text-[#8E8E93]">{s.level || "—"}</td>
                <td class="px-4 py-3 text-[#8E8E93]">{s.type || "—"}</td>
                <td class="px-4 py-3 text-right">{format_int(s.student_count)}</td>
              </tr>
              <tr :if={@schools == []}>
                <td colspan="5" class="px-4 py-10 text-center text-[#8E8E93]">
                  No schools match.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :accent, :string, default: "text-[#1C1C1E]"

  defp count_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-5">
      <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-medium">{@label}</div>
      <div class={["text-3xl font-bold mt-1", @accent]}>{format_int(@count)}</div>
    </div>
    """
  end

  defp country_state(school, countries) do
    country =
      Enum.find_value(countries, "", fn c ->
        if c.id == school.country_id, do: c.name
      end)

    state =
      case school.state_id do
        nil ->
          nil

        state_id ->
          case Geo.get_state(state_id) do
            %{name: name} -> name
            _ -> nil
          end
      end

    cond do
      country == "" and is_nil(state) -> "—"
      is_nil(state) -> country
      country == "" -> state
      true -> "#{country} · #{state}"
    end
  end

  defp format_int(nil), do: "—"

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_int(_), do: "—"
end
