defmodule FunSheepWeb.UserProfileLive do
  use FunSheepWeb, :live_view

  import Ecto.Query, warn: false

  alias FunSheep.{Accounts, Gamification, Social, Repo}
  alias FunSheep.Gamification.{Achievement, XpEvent}

  @impl true
  def mount(%{"id" => profile_id}, _session, socket) do
    viewer_id = socket.assigns.current_user["id"]

    case Ecto.UUID.cast(profile_id) do
      :error ->
        {:ok, socket |> put_flash(:error, "Profile not found.") |> redirect(to: ~p"/leaderboard")}

      {:ok, _} ->
        profile = Accounts.get_user_role(profile_id)

        cond do
          is_nil(profile) ->
            {:ok,
             socket
             |> put_flash(:error, "Profile not found.")
             |> redirect(to: ~p"/leaderboard")}

          profile_id == viewer_id ->
            # Self — redirect to dashboard
            {:ok, socket |> redirect(to: ~p"/dashboard")}

          not Social.can_view_profile?(viewer_id, profile_id) ->
            {:ok,
             socket
             |> put_flash(:error, "You don't have access to this profile.")
             |> redirect(to: ~p"/leaderboard")}

          true ->
            load_profile(socket, viewer_id, profile)
        end
    end
  end

  @impl true
  def handle_event("follow", _params, socket) do
    viewer_id = socket.assigns.current_user["id"]
    Social.follow(viewer_id, socket.assigns.profile.id)
    {:noreply, reload_follow_state(socket, viewer_id)}
  end

  @impl true
  def handle_event("unfollow", _params, socket) do
    viewer_id = socket.assigns.current_user["id"]
    Social.unfollow(viewer_id, socket.assigns.profile.id)
    {:noreply, reload_follow_state(socket, viewer_id)}
  end

  @impl true
  def handle_event("block", _params, socket) do
    viewer_id = socket.assigns.current_user["id"]
    Social.block(viewer_id, socket.assigns.profile.id)

    {:noreply,
     socket
     |> put_flash(:info, "User blocked.")
     |> redirect(to: ~p"/leaderboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-lg mx-auto">
      <%!-- Back link --%>
      <div class="animate-slide-up">
        <.link navigate={~p"/leaderboard"} class="text-sm text-gray-400 hover:text-gray-600 flex items-center gap-1">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
          </svg>
          Back to Flock
        </.link>
      </div>

      <%!-- Profile Card --%>
      <div class="bg-white rounded-2xl border border-gray-100 p-6 shadow-sm animate-slide-up">
        <div class="flex items-start gap-4">
          <%!-- Avatar --%>
          <div class={[
            "w-16 h-16 rounded-full flex items-center justify-center text-2xl font-extrabold shrink-0",
            avatar_class(@follow_state)
          ]}>
            {avatar_initial(@profile.display_name)}
          </div>

          <%!-- Name + meta --%>
          <div class="flex-1 min-w-0">
            <h1 class="text-xl font-extrabold text-gray-900 truncate">
              {@profile.display_name}
              <span :if={@follow_state == :mutual} class="text-[#4CD964] ml-1">♥</span>
            </h1>
            <p class="text-sm text-gray-500 mt-0.5">
              {grade_label(@profile.grade)}
              {school_label(@profile)}
            </p>
            <p :if={@mutual_count > 0} class="text-xs text-gray-400 mt-1">
              {@mutual_count} mutual {if @mutual_count == 1, do: "follow", else: "follows"}
            </p>
          </div>
        </div>

        <%!-- Action buttons --%>
        <div class="flex gap-2 mt-4">
          <button
            :if={@follow_state in [:none, :not_following, :followed_by]}
            phx-click="follow"
            class="flex-1 py-2 rounded-full text-sm font-bold bg-[#4CD964] text-white hover:bg-[#3DBF55] transition-colors shadow-md"
          >
            + Follow
          </button>
          <button
            :if={@follow_state in [:following, :mutual]}
            phx-click="unfollow"
            class="flex-1 py-2 rounded-full text-sm font-bold bg-gray-100 text-gray-600 hover:bg-gray-200 transition-colors"
          >
            {if @follow_state == :mutual, do: "Friends ♥", else: "Following"}
          </button>
        </div>

        <%!-- Followed-by notice --%>
        <p :if={@follow_state == :followed_by} class="text-xs text-gray-400 text-center mt-1">
          Follows you
        </p>
      </div>

      <%!-- Stats Row --%>
      <div class="grid grid-cols-3 gap-3 animate-slide-up">
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-orange-500">{@streak}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Day Streak</p>
        </div>
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-[#4CD964]">{@weekly_xp}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">FP This Week</p>
        </div>
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-pink-500">{length(@achievements)}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Badges</p>
        </div>
      </div>

      <%!-- Follower/Following row --%>
      <div class="grid grid-cols-2 gap-3 animate-slide-up">
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-xl font-extrabold text-gray-900">{@follower_count}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Followers</p>
        </div>
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-xl font-extrabold text-gray-900">{@following_count}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Following</p>
        </div>
      </div>

      <%!-- Badges --%>
      <div :if={@achievements != []} class="bg-white rounded-2xl border border-gray-100 p-5 animate-slide-up">
        <h2 class="text-sm font-extrabold text-gray-900 mb-3">Badges</h2>
        <div class="grid grid-cols-4 sm:grid-cols-6 gap-2">
          <div
            :for={achievement <- @achievements}
            class="flex flex-col items-center text-center"
            title={Achievement.display_info(achievement.achievement_type).name}
          >
            <span class="text-2xl">{Achievement.display_info(achievement.achievement_type).emoji}</span>
            <span class="text-[9px] text-gray-400 mt-0.5 leading-tight">
              {Achievement.display_info(achievement.achievement_type).name}
            </span>
          </div>
        </div>
      </div>

      <%!-- Flock Tree --%>
      <div
        :if={@flock_tree.invited_by != nil or @flock_tree.invited_users != []}
        class="bg-white rounded-2xl border border-gray-100 p-5 animate-slide-up"
      >
        <h2 class="text-sm font-extrabold text-gray-900 mb-3">🐑 Flock Tree</h2>

        <div :if={@flock_tree.invited_by} class="flex items-center gap-2 mb-3">
          <div class="w-7 h-7 rounded-full bg-purple-100 flex items-center justify-center text-xs font-bold text-purple-600 shrink-0">
            {avatar_initial(@flock_tree.invited_by.display_name)}
          </div>
          <span class="text-xs text-gray-500">
            Invited by <span class="font-semibold text-gray-700">{@flock_tree.invited_by.display_name}</span>
          </span>
        </div>

        <div :if={@flock_tree.invited_users != []}>
          <p class="text-xs text-gray-400 font-semibold uppercase tracking-wide mb-2">
            Brought to the flock
            <span :if={@flock_tree.total_invited > length(@flock_tree.invited_users)}>
              ({@flock_tree.total_invited} total)
            </span>
          </p>
          <div class="flex flex-wrap gap-2">
            <div
              :for={invitee <- @flock_tree.invited_users}
              class="flex items-center gap-1.5 bg-[#4CD964]/10 rounded-full px-3 py-1"
            >
              <div class="w-5 h-5 rounded-full bg-[#4CD964]/30 flex items-center justify-center text-[10px] font-bold text-green-700">
                {avatar_initial(invitee.display_name)}
              </div>
              <span class="text-xs font-medium text-green-800">{invitee.display_name}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Block option (collapsed) --%>
      <div class="text-center animate-slide-up">
        <button
          phx-click="block"
          data-confirm={"Block #{@profile.display_name}? They won't be able to see your profile."}
          class="text-xs text-gray-300 hover:text-red-400 transition-colors"
        >
          Block this user
        </button>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp load_profile(socket, viewer_id, profile) do
    follow_state = Social.follow_state(viewer_id, profile.id)
    achievements = Gamification.list_achievements(profile.id)
    {:ok, streak_rec} = Gamification.get_or_create_streak(profile.id)

    window_start =
      Date.utc_today()
      |> Date.add(-7)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    weekly_xp =
      Repo.one(
        from(xp in XpEvent,
          where: xp.user_role_id == ^profile.id and xp.inserted_at >= ^window_start,
          select: coalesce(sum(xp.amount), 0)
        )
      ) || 0

    mutual_count = mutual_follow_count(viewer_id, profile.id)
    follower_count = Social.follower_count(profile.id)
    following_count = Social.following_count(profile.id)
    flock_tree = Social.flock_tree(profile.id)

    {:ok,
     assign(socket,
       page_title: profile.display_name,
       profile: profile,
       follow_state: follow_state,
       achievements: achievements,
       streak: streak_rec.current_streak,
       weekly_xp: weekly_xp,
       mutual_count: mutual_count,
       follower_count: follower_count,
       following_count: following_count,
       flock_tree: flock_tree
     )}
  end

  defp reload_follow_state(socket, viewer_id) do
    profile = socket.assigns.profile
    follow_state = Social.follow_state(viewer_id, profile.id)
    mutual_count = mutual_follow_count(viewer_id, profile.id)
    follower_count = Social.follower_count(profile.id)

    assign(socket,
      follow_state: follow_state,
      mutual_count: mutual_count,
      follower_count: follower_count
    )
  end

  defp mutual_follow_count(viewer_id, subject_id) do
    viewer_following = MapSet.new(Social.following_ids(viewer_id))
    subject_following = MapSet.new(Social.following_ids(subject_id))
    MapSet.intersection(viewer_following, subject_following) |> MapSet.size()
  end

  defp avatar_initial(nil), do: "?"
  defp avatar_initial(name), do: String.first(name)

  defp avatar_class(:mutual),
    do: "bg-gradient-to-br from-[#4CD964] to-emerald-600 text-white ring-4 ring-green-200"

  defp avatar_class(:following), do: "bg-blue-100 text-blue-600"
  defp avatar_class(:followed_by), do: "bg-purple-100 text-purple-600"
  defp avatar_class(_), do: "bg-gray-100 text-gray-600"

  defp grade_label(nil), do: ""
  defp grade_label(g), do: "Grade #{g}"

  defp school_label(%{school: %{name: name}}) when is_binary(name), do: " · #{name}"
  defp school_label(_), do: ""

end
