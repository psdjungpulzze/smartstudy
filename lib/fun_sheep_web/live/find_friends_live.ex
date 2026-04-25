defmodule FunSheepWeb.FindFriendsLive do
  use FunSheepWeb, :live_view

  alias FunSheep.Social
  alias FunSheep.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]
    suggestions = Social.suggested_follows(user_role_id, 12)
    following_count = Social.following_count(user_role_id)

    {:ok,
     assign(socket,
       page_title: "Find Friends",
       query: "",
       search_results: [],
       suggestions: suggestions,
       following_count: following_count,
       invite_email: "",
       invite_status: nil
     )}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    trimmed = String.trim(query)

    results =
      if String.length(trimmed) >= 2 do
        Social.search_peers(user_role_id, trimmed)
      else
        []
      end

    {:noreply, assign(socket, query: query, search_results: results)}
  end

  @impl true
  def handle_event("follow", %{"id" => target_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    Social.follow(user_role_id, target_id, "manual")

    suggestions = Social.suggested_follows(user_role_id, 12)
    following_count = Social.following_count(user_role_id)

    results =
      if String.length(String.trim(socket.assigns.query)) >= 2 do
        Social.search_peers(user_role_id, String.trim(socket.assigns.query))
      else
        []
      end

    {:noreply,
     assign(socket,
       suggestions: suggestions,
       following_count: following_count,
       search_results: results
     )}
  end

  @impl true
  def handle_event("unfollow", %{"id" => target_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    Social.unfollow(user_role_id, target_id)

    suggestions = Social.suggested_follows(user_role_id, 12)
    following_count = Social.following_count(user_role_id)

    results =
      if String.length(String.trim(socket.assigns.query)) >= 2 do
        Social.search_peers(user_role_id, String.trim(socket.assigns.query))
      else
        []
      end

    {:noreply,
     assign(socket,
       suggestions: suggestions,
       following_count: following_count,
       search_results: results
     )}
  end

  @impl true
  def handle_event("send_invite", %{"invite_email" => email}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    trimmed = String.trim(email)

    if trimmed == "" do
      {:noreply, assign(socket, invite_status: {:error, "Please enter an email address."})}
    else
      case Accounts.get_user_role_by_email(trimmed) do
        nil ->
          case Social.create_invite(user_role_id, invitee_email: trimmed) do
            {:ok, _invite} ->
              {:noreply, assign(socket, invite_email: "", invite_status: {:ok, "Invite sent to #{trimmed}!"})}

            {:error, _} ->
              {:noreply, assign(socket, invite_status: {:error, "Couldn't send invite. Please try again."})}
          end

        %{id: invitee_id} ->
          case Social.create_invite(user_role_id, invitee_user_role_id: invitee_id) do
            {:ok, _invite} ->
              {:noreply, assign(socket, invite_email: "", invite_status: {:ok, "Invite sent to #{trimmed}!"})}

            {:error, _} ->
              {:noreply, assign(socket, invite_status: {:error, "Couldn't send invite. Please try again."})}
          end
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-lg mx-auto">
      <%!-- Header --%>
      <div class="animate-slide-up">
        <.link navigate={~p"/leaderboard"} class="text-sm text-gray-400 hover:text-gray-600 flex items-center gap-1 mb-4">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Back to Flock
        </.link>
        <h1 class="text-2xl font-extrabold text-gray-900">Find Friends</h1>
        <p class="text-sm text-gray-500 mt-0.5">
          You're following {@following_count} {if @following_count == 1, do: "student", else: "students"}
        </p>
      </div>

      <%!-- Search --%>
      <div class="animate-slide-up">
        <form phx-change="search" class="relative">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search classmates by name..."
            class="w-full rounded-full border border-gray-200 px-4 py-3 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-[#4CD964] focus:border-transparent"
            phx-debounce="300"
          />
          <svg
            class="absolute right-3 top-3 w-5 h-5 text-gray-400"
            fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
          </svg>
        </form>
      </div>

      <%!-- Search results --%>
      <div :if={@search_results != []} class="space-y-2 animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-900">Results</h2>
        <.peer_card :for={result <- @search_results} peer={result.user_role} follow_state={result.follow_state} />
      </div>

      <div :if={String.length(String.trim(@query)) >= 2 and @search_results == []} class="text-center py-6 animate-slide-up">
        <p class="text-gray-400 text-sm">No classmates found for "{@query}"</p>
      </div>

      <%!-- Suggestions --%>
      <div :if={@query == "" and @suggestions != []} class="space-y-2 animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-900">People You Might Know</h2>
        <.peer_card
          :for={suggestion <- @suggestions}
          peer={suggestion.user_role}
          follow_state={:none}
          reason={suggestion.reason}
        />
      </div>

      <div :if={@query == "" and @suggestions == []} class="bg-white rounded-2xl border border-gray-100 p-8 text-center animate-slide-up">
        <p class="text-3xl mb-3">🐑</p>
        <h3 class="font-extrabold text-gray-900">No suggestions yet</h3>
        <p class="text-sm text-gray-500 mt-1">
          Set your school in your profile to find classmates.
        </p>
      </div>

      <%!-- Invite by email --%>
      <div :if={@query == ""} class="animate-slide-up">
        <div class="bg-white rounded-2xl border border-gray-100 p-4 space-y-3">
          <h2 class="text-sm font-extrabold text-gray-900">Invite a Friend by Email</h2>
          <p class="text-xs text-gray-400">
            Not all classmates are on FunSheep yet. Send them an invite link!
          </p>

          <form phx-submit="send_invite" class="flex gap-2">
            <input
              type="email"
              name="invite_email"
              value={@invite_email}
              placeholder="friend@school.com"
              required
              class="flex-1 rounded-full border border-gray-200 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#4CD964] focus:border-transparent"
            />
            <button
              type="submit"
              class="px-4 py-2 rounded-full bg-[#4CD964] text-white text-sm font-bold hover:bg-[#3DBF55] transition-colors"
            >
              Send
            </button>
          </form>

          <p :if={@invite_status} class={[
            "text-xs font-medium",
            match?({:ok, _}, @invite_status) && "text-[#4CD964]",
            match?({:error, _}, @invite_status) && "text-red-500"
          ]}>
            {elem(@invite_status, 1)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ── Peer Card Component ────────────────────────────────────────────────────

  attr :peer, :map, required: true
  attr :follow_state, :atom, required: true
  attr :reason, :atom, default: nil

  defp peer_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-100 p-3 flex items-center gap-3">
      <.link navigate={~p"/social/profile/#{@peer.id}"} class="shrink-0">
        <div class={[
          "w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold hover:opacity-80 transition-opacity",
          peer_avatar_class(@follow_state)
        ]}>
          {String.first(@peer.display_name || "?")}
        </div>
      </.link>

      <div class="flex-1 min-w-0">
        <.link navigate={~p"/social/profile/#{@peer.id}"} class="hover:underline">
          <p class="font-bold text-sm text-gray-900 truncate">
            {@peer.display_name}
            <span :if={@follow_state == :mutual} class="text-[#4CD964] ml-1 text-xs">♥</span>
          </p>
        </.link>
        <p :if={@reason} class="text-xs text-gray-400 mt-0.5">
          {reason_label(@reason)}
        </p>
        <p :if={is_nil(@reason)} class="text-xs text-gray-400 mt-0.5">
          {grade_label(@peer.grade)}
        </p>
      </div>

      <div class="shrink-0">
        <button
          :if={@follow_state in [:none, :followed_by]}
          phx-click="follow"
          phx-value-id={@peer.id}
          class="text-xs px-3 py-1 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors"
        >
          + Follow
        </button>
        <button
          :if={@follow_state in [:following, :mutual]}
          phx-click="unfollow"
          phx-value-id={@peer.id}
          class="text-xs px-3 py-1 rounded-full bg-gray-100 text-gray-500 font-bold hover:bg-gray-200 transition-colors"
        >
          {if @follow_state == :mutual, do: "Friends ♥", else: "Following"}
        </button>
      </div>
    </div>
    """
  end

  defp peer_avatar_class(:mutual),
    do: "bg-gradient-to-br from-[#4CD964] to-emerald-600 text-white ring-2 ring-green-200"

  defp peer_avatar_class(:following), do: "bg-blue-100 text-blue-600"
  defp peer_avatar_class(_), do: "bg-gray-100 text-gray-600"

  defp reason_label(:school), do: "🏫 Same school"
  defp reason_label(:course), do: "📚 Shared course"
  defp reason_label(:flock), do: "⚡ In your Flock"
  defp reason_label(:fof), do: "👥 Friend of a friend"
  defp reason_label(_), do: "Suggested for you"

  defp grade_label(nil), do: "Student"
  defp grade_label(g), do: "Grade #{g}"
end
