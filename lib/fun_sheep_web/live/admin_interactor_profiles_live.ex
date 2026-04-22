defmodule FunSheepWeb.AdminInteractorProfilesLive do
  @moduledoc """
  /admin/interactor/profiles — personalization debugger.

  Answers "why is the tutor talking to this 5th-grader like a college
  student?" by surfacing the Interactor user-profile raw + effective
  (merged) representations side-by-side, allowing inline edits that
  write through `FunSheep.Interactor.Profiles.update_profile/2`.

  Every save writes an `admin.profile.update` audit entry.
  """
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Admin}
  alias FunSheep.Interactor.Profiles

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Interactor profiles · Admin")
     |> assign(:search, "")
     |> assign(:matching_users, [])
     |> assign(:selected, nil)
     |> assign(:raw_profile, nil)
     |> assign(:effective_profile, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    matches =
      if String.length(term) < 2 do
        []
      else
        Accounts.list_users_for_admin(search: term, limit: 10, offset: 0)
      end

    {:noreply,
     socket
     |> assign(:search, term)
     |> assign(:matching_users, matches)}
  end

  def handle_event("select_user", %{"id" => user_id}, socket) do
    user = Accounts.get_user_role!(user_id)
    {:noreply, load_profile(socket, user)}
  end

  def handle_event("save_profile", %{"profile" => attrs}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick a user first.")}

      user ->
        parsed = decode_profile_fields(attrs)

        case Profiles.update_profile(user.interactor_user_id, parsed) do
          {:ok, _} ->
            Admin.record(%{
              actor_user_role_id: get_in(socket.assigns, [:current_user, "user_role_id"]),
              actor_label:
                "admin:#{get_in(socket.assigns, [:current_user, "email"]) || "unknown"}",
              action: "admin.profile.update",
              target_type: "user_role",
              target_id: user.id,
              metadata: %{"keys" => Map.keys(parsed)}
            })

            {:noreply,
             socket
             |> put_flash(:info, "Profile saved.")
             |> load_profile(user)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("refresh", _, socket) do
    case socket.assigns.selected do
      nil -> {:noreply, socket}
      user -> {:noreply, load_profile(socket, user)}
    end
  end

  defp load_profile(socket, user) do
    {raw, effective, err} = fetch_profiles(user.interactor_user_id)

    socket
    |> assign(:selected, user)
    |> assign(:raw_profile, raw)
    |> assign(:effective_profile, effective)
    |> assign(:error, err)
  end

  defp fetch_profiles(external_user_id) do
    raw =
      case Profiles.get_profile(external_user_id) do
        {:ok, %{"data" => data}} -> data
        {:ok, data} -> data
        _ -> nil
      end

    effective =
      case Profiles.get_effective_profile(external_user_id) do
        {:ok, %{"data" => data}} -> data
        {:ok, data} -> data
        _ -> nil
      end

    err =
      if is_nil(raw) and is_nil(effective) do
        "Interactor service is unavailable or returned no data."
      end

    {raw, effective, err}
  end

  defp decode_profile_fields(attrs) do
    %{
      "grade" => attrs["grade"] || "",
      "hobbies" => split_list(attrs["hobbies"]),
      "learning_preference" => attrs["learning_preference"] || "",
      "custom_instructions" => attrs["custom_instructions"] || ""
    }
  end

  defp split_list(nil), do: []
  defp split_list(""), do: []

  defp split_list(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-6xl mx-auto">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-[#1C1C1E]">Interactor profiles</h1>
        <p class="text-[#8E8E93] text-sm mt-1">
          Inspect and edit the Interactor user profile — grade, hobbies,
          learning preferences, custom instructions — that drives agent
          personalization. Every save is audited.
        </p>
      </div>

      <div class="bg-white rounded-2xl shadow-md p-4 mb-4">
        <form phx-change="search" class="flex items-center gap-3">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search user by email or name…"
            phx-debounce="300"
            class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </form>
        <ul :if={@matching_users != []} class="mt-3 divide-y divide-[#F5F5F7] text-sm">
          <li
            :for={u <- @matching_users}
            class="py-2 flex items-center justify-between cursor-pointer hover:bg-[#F5F5F7] px-2 rounded-xl"
            phx-click="select_user"
            phx-value-id={u.id}
          >
            <div>
              <span class="font-medium text-[#1C1C1E]">{u.email}</span>
              <span class="text-[#8E8E93] ml-2">{u.display_name || "—"}</span>
            </div>
            <span class="text-xs text-[#8E8E93]">{String.capitalize(Atom.to_string(u.role))}</span>
          </li>
        </ul>
      </div>

      <div
        :if={@selected == nil}
        class="bg-white rounded-2xl shadow-md p-12 text-center text-[#8E8E93]"
      >
        Pick a user to view their Interactor profile.
      </div>

      <div :if={@selected} class="space-y-4">
        <div class="bg-white rounded-2xl shadow-md p-5 flex items-center justify-between">
          <div>
            <div class="font-semibold text-[#1C1C1E]">{@selected.email}</div>
            <div class="text-xs text-[#8E8E93]">
              Interactor user id: <code>{@selected.interactor_user_id}</code>
            </div>
          </div>
          <button
            type="button"
            phx-click="refresh"
            class="px-3 py-1 rounded-full text-xs font-medium border border-[#E5E5EA] hover:bg-[#F5F5F7]"
          >
            Refresh
          </button>
        </div>

        <div
          :if={@error}
          class="bg-[#FFE5E3] text-[#FF3B30] rounded-xl p-4 text-sm"
        >
          {@error}
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.profile_editor raw={@raw_profile} />
          <.effective_preview effective={@effective_profile} />
        </div>
      </div>
    </div>
    """
  end

  attr :raw, :map, required: true

  defp profile_editor(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">User profile (raw)</h2>
      <form phx-submit="save_profile" class="space-y-3 text-sm">
        <label class="block">
          <span class="text-xs uppercase tracking-wide text-[#8E8E93]">Grade</span>
          <input
            type="text"
            name="profile[grade]"
            value={field(@raw, "grade")}
            class="w-full px-4 py-2 bg-[#F5F5F7] rounded-full border border-transparent focus:border-[#4CD964] outline-none mt-1"
            placeholder="e.g. 5"
          />
        </label>

        <label class="block">
          <span class="text-xs uppercase tracking-wide text-[#8E8E93]">
            Hobbies (comma-separated)
          </span>
          <input
            type="text"
            name="profile[hobbies]"
            value={join_list(field(@raw, "hobbies"))}
            class="w-full px-4 py-2 bg-[#F5F5F7] rounded-full border border-transparent focus:border-[#4CD964] outline-none mt-1"
            placeholder="soccer, painting, minecraft"
          />
        </label>

        <label class="block">
          <span class="text-xs uppercase tracking-wide text-[#8E8E93]">Learning preference</span>
          <input
            type="text"
            name="profile[learning_preference]"
            value={field(@raw, "learning_preference")}
            class="w-full px-4 py-2 bg-[#F5F5F7] rounded-full border border-transparent focus:border-[#4CD964] outline-none mt-1"
            placeholder="visual / auditory / hands-on"
          />
        </label>

        <label class="block">
          <span class="text-xs uppercase tracking-wide text-[#8E8E93]">Custom instructions</span>
          <textarea
            name="profile[custom_instructions]"
            rows="4"
            class="w-full px-4 py-2 bg-[#F5F5F7] rounded-xl border border-transparent focus:border-[#4CD964] outline-none mt-1 font-mono text-xs"
            placeholder="Extra context for the tutor…"
          >{field(@raw, "custom_instructions")}</textarea>
        </label>

        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md"
        >
          Save
        </button>
      </form>
    </section>
    """
  end

  attr :effective, :map, required: true

  defp effective_preview(assigns) do
    ~H"""
    <section class="bg-white rounded-2xl shadow-md p-6">
      <h2 class="font-semibold text-[#1C1C1E] mb-3">Effective profile (merged)</h2>
      <p class="text-xs text-[#8E8E93] mb-3">
        What the agent will actually see when called — this is the raw user
        profile merged with defaults and app-level context.
      </p>
      <pre class="text-xs bg-[#F5F5F7] p-3 rounded-lg whitespace-pre-wrap break-all">{format_effective(@effective)}</pre>
    </section>
    """
  end

  defp field(nil, _key), do: ""
  defp field(map, key) when is_map(map), do: Map.get(map, key, "") |> to_string()
  defp field(_, _key), do: ""

  defp join_list(nil), do: ""
  defp join_list(list) when is_list(list), do: Enum.join(list, ", ")
  defp join_list(other), do: to_string(other)

  defp format_effective(nil), do: "(no data)"
  defp format_effective(%{} = map) when map_size(map) == 0, do: "(empty)"
  defp format_effective([]), do: "(empty)"

  defp format_effective(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(data, pretty: true)
    end
  end
end
