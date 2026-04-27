defmodule FunSheepWeb.FlockProfileLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  alias FunSheep.{Accounts, Gamification, Social}

  @impl true
  def mount(%{"id" => profile_id}, _session, socket) do
    viewer_id = socket.assigns.current_user["id"]

    case Accounts.get_user_role(profile_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> push_navigate(to: ~p"/leaderboard")}

      profile ->
        gamification = Gamification.dashboard_summary(profile_id)
        achievements = Gamification.list_achievements(profile_id)
        follow_state = Social.follow_state(viewer_id, profile_id)
        follower_count = Social.follower_count(profile_id)
        following_count = Social.following_count(profile_id)

        {:ok,
         assign(socket,
           page_title: profile.display_name || "Profile",
           profile: profile,
           gamification: gamification,
           achievements: achievements,
           follow_state: follow_state,
           follower_count: follower_count,
           following_count: following_count,
           viewer_id: viewer_id
         )}
    end
  end

  @impl true
  def handle_event("follow", _params, socket) do
    case Social.follow(socket.assigns.viewer_id, socket.assigns.profile.id) do
      {:ok, _} ->
        new_state = Social.follow_state(socket.assigns.viewer_id, socket.assigns.profile.id)
        follower_count = Social.follower_count(socket.assigns.profile.id)
        {:noreply, assign(socket, follow_state: new_state, follower_count: follower_count)}

      {:error, :blocked} ->
        {:noreply, put_flash(socket, :error, "Unable to follow this user")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  @impl true
  def handle_event("unfollow", _params, socket) do
    :ok = Social.unfollow(socket.assigns.viewer_id, socket.assigns.profile.id)
    new_state = Social.follow_state(socket.assigns.viewer_id, socket.assigns.profile.id)
    follower_count = Social.follower_count(socket.assigns.profile.id)
    {:noreply, assign(socket, follow_state: new_state, follower_count: follower_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-lg mx-auto">
      <%!-- Back link --%>
      <.link
        navigate={~p"/leaderboard"}
        class="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        ← Back to Flock
      </.link>

      <%!-- Profile card --%>
      <div class="bg-white rounded-2xl border border-gray-100 p-6 shadow-sm">
        <div class="flex items-start gap-4">
          <%!-- Avatar --%>
          <div class="w-16 h-16 rounded-full bg-gradient-to-br from-gray-200 to-gray-300 text-gray-700 flex items-center justify-center text-2xl font-extrabold shrink-0">
            {String.first(@profile.display_name || "?")}
          </div>

          <%!-- Name + role --%>
          <div class="flex-1 min-w-0">
            <h1 class="text-xl font-extrabold text-gray-900 truncate">
              {@profile.display_name || "Anonymous"}
            </h1>
            <p class="text-sm text-gray-500 capitalize mt-0.5">{@profile.role}</p>

            <%!-- Follower / following counts --%>
            <div class="flex gap-4 mt-2">
              <div class="text-center">
                <p class="text-base font-extrabold text-gray-900">{@follower_count}</p>
                <p class="text-[10px] text-gray-400 font-bold">Followers</p>
              </div>
              <div class="text-center">
                <p class="text-base font-extrabold text-gray-900">{@following_count}</p>
                <p class="text-[10px] text-gray-400 font-bold">Following</p>
              </div>
            </div>
          </div>

          <%!-- Sheep mascot --%>
          <.sheep
            state={@gamification.sheep_state}
            size="sm"
            wool_level={@gamification.streak.wool_level}
          />
        </div>

        <%!-- Follow / Unfollow button --%>
        <div :if={@follow_state != :self} class="mt-4">
          <button
            :if={@follow_state in [:not_following]}
            phx-click="follow"
            class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-bold py-2.5 rounded-full shadow-md transition-colors"
          >
            Follow
          </button>
          <button
            :if={@follow_state == :following}
            phx-click="unfollow"
            class="w-full bg-gray-100 hover:bg-gray-200 text-gray-700 font-bold py-2.5 rounded-full transition-colors"
          >
            Following ✓
          </button>
          <button
            :if={@follow_state == :mutual}
            phx-click="unfollow"
            class="w-full bg-green-50 hover:bg-gray-100 text-[#4CD964] font-bold py-2.5 rounded-full border border-[#4CD964] transition-colors"
          >
            Friends 🤝
          </button>
          <div
            :if={@follow_state == :blocked}
            class="w-full text-center text-sm text-gray-400 py-2.5"
          >
            Unavailable
          </div>
        </div>
        <div :if={@follow_state == :self} class="mt-4">
          <.link
            navigate={~p"/profile/setup"}
            class="block w-full text-center bg-gray-100 text-gray-600 font-bold py-2.5 rounded-full hover:bg-gray-200 transition-colors"
          >
            Edit Profile
          </.link>
        </div>
      </div>

      <%!-- Stats --%>
      <div class="grid grid-cols-3 gap-3">
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-orange-500">
            {@gamification.streak.current_streak}
          </p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Day Streak</p>
        </div>
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-amber-500">{@gamification.total_xp}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Total FP</p>
        </div>
        <div class="bg-white rounded-2xl border border-gray-100 p-4 text-center">
          <p class="text-2xl font-extrabold text-pink-500">{length(@achievements)}</p>
          <p class="text-xs text-gray-500 font-bold mt-0.5">Badges</p>
        </div>
      </div>

      <%!-- Achievements --%>
      <div :if={@achievements != []} class="space-y-3">
        <h3 class="text-sm font-extrabold text-gray-900">Badges</h3>
        <div class="grid grid-cols-3 sm:grid-cols-4 gap-3">
          <div
            :for={achievement <- @achievements}
            class="bg-white rounded-2xl border border-gray-100 p-3 text-center"
          >
            <div class="text-2xl mb-1">
              {FunSheep.Gamification.Achievement.display_info(achievement.achievement_type).emoji}
            </div>
            <p class="text-[10px] font-bold text-gray-600 leading-tight">
              {FunSheep.Gamification.Achievement.display_info(achievement.achievement_type).name}
            </p>
          </div>
        </div>
      </div>

      <div
        :if={@achievements == []}
        class="bg-white rounded-2xl border border-gray-100 p-6 text-center"
      >
        <p class="text-gray-400 text-sm">No badges earned yet</p>
      </div>
    </div>
    """
  end
end
