defmodule FunSheepWeb.LeaderboardLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  alias FunSheep.Gamification
  alias FunSheep.Gamification.{Achievement, ShoutOut}
  alias FunSheep.Social

  @impl true
  def mount(_params, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    {achievements, gamification, flock, my_rank, flock_size, school_peers} =
      case Ecto.UUID.cast(user_role_id) do
        {:ok, _uuid} ->
          achv = Gamification.list_achievements(user_role_id)
          gam = Gamification.dashboard_summary(user_role_id)
          {flock_list, rank, size} = Social.flock_with_social(user_role_id)
          peers = Social.school_peers(user_role_id, limit: 50)
          {achv, gam, flock_list, rank, size, peers}

        :error ->
          {[], default_gamification(), [], 0, 0, []}
      end

    shout_outs = Gamification.get_current_shout_outs()

    {:ok,
     assign(socket,
       page_title: "Flock",
       tab: :leaderboard,
       flock_filter: :all,
       achievements: achievements,
       gamification: gamification,
       flock: flock,
       my_rank: my_rank,
       flock_size: flock_size,
       shout_outs: shout_outs,
       school_peers: school_peers
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ["leaderboard", "achievements", "shout_outs", "school"] do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("set_flock_filter", %{"filter" => filter}, socket)
      when filter in ["all", "following", "mutual"] do
    user_role_id = socket.assigns.current_user["id"]
    filter_atom = String.to_existing_atom(filter)

    {flock, my_rank, flock_size} =
      Social.flock_with_social(user_role_id, filter: filter_atom)

    {:noreply,
     assign(socket,
       flock_filter: filter_atom,
       flock: flock,
       my_rank: my_rank,
       flock_size: flock_size
     )}
  end

  @impl true
  def handle_event("follow", %{"id" => target_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    Social.follow(user_role_id, target_id)

    socket = refresh_social(socket, user_role_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("unfollow", %{"id" => target_id}, socket) do
    user_role_id = socket.assigns.current_user["id"]
    Social.unfollow(user_role_id, target_id)

    socket = refresh_social(socket, user_role_id)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between animate-slide-up">
        <div>
          <h1 class="text-2xl font-extrabold text-gray-900">The Flock</h1>
          <p class="text-sm text-gray-500 mt-0.5">
            {league_name(@my_rank)} League · Week of {Calendar.strftime(week_start(), "%b %d")}
          </p>
        </div>
        <.sheep
          state={@gamification.sheep_state}
          size="md"
          wool_level={@gamification.streak.wool_level}
        />
      </div>

      <%!-- Tab Selector --%>
      <div class="flex gap-2 flex-wrap animate-slide-up">
        <button
          phx-click="switch_tab"
          phx-value-tab="leaderboard"
          class={tab_class(@tab == :leaderboard)}
        >
          Leaderboard
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="achievements"
          class={tab_class(@tab == :achievements)}
        >
          Badges
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="shout_outs"
          class={tab_class(@tab == :shout_outs)}
        >
          ✨ Shout Outs
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="school"
          class={tab_class(@tab == :school)}
        >
          🏫 School
        </button>
      </div>

      <%!-- ═══ Leaderboard Tab ═══ --%>
      <div :if={@tab == :leaderboard} class="space-y-4 animate-slide-up">
        <%!-- Social filter --%>
        <div class="flex gap-2">
          <button
            phx-click="set_flock_filter"
            phx-value-filter="all"
            class={filter_class(@flock_filter == :all)}
          >
            Everyone
          </button>
          <button
            phx-click="set_flock_filter"
            phx-value-filter="following"
            class={filter_class(@flock_filter == :following)}
          >
            Following
          </button>
          <button
            phx-click="set_flock_filter"
            phx-value-filter="mutual"
            class={filter_class(@flock_filter == :mutual)}
          >
            ♥ Friends
          </button>
        </div>

        <%!-- Empty following/mutual state --%>
        <div
          :if={@flock == [] and @flock_filter != :all}
          class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
        >
          <p class="text-3xl mb-3">{if @flock_filter == :mutual, do: "♥", else: "👥"}</p>
          <h3 class="font-extrabold text-gray-900 text-lg">
            {if @flock_filter == :mutual,
              do: "No friends yet",
              else: "You're not following anyone"}
          </h3>
          <p class="text-sm text-gray-500 mt-1">
            {if @flock_filter == :mutual,
              do: "When you and someone both follow each other, they appear here.",
              else: "Follow classmates from the School tab to see their rankings."}
          </p>
          <button
            phx-click="switch_tab"
            phx-value-tab="school"
            class="mt-4 px-4 py-2 rounded-full text-sm font-bold bg-[#4CD964] text-white shadow-md"
          >
            Find Classmates
          </button>
        </div>

        <%!-- Podium: Top 3 --%>
        <.podium :if={length(@flock) >= 3 and @flock_filter == :all} flock={@flock} />

        <%!-- Your Position Card --%>
        <div class="bg-gradient-to-r from-[#4CD964] to-emerald-500 rounded-2xl p-4 text-white shadow-lg">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center text-lg font-extrabold">
              #{@my_rank}
            </div>
            <div class="flex-1">
              <p class="font-extrabold">You</p>
              <p class="text-xs text-green-100">
                {rank_message(@my_rank, @flock_size)}
              </p>
            </div>
            <div class="text-right">
              <p class="text-xl font-extrabold">
                {find_my_xp(@flock)}
              </p>
              <p class="text-xs text-green-100">FP this week</p>
            </div>
          </div>
        </div>

        <%!-- Full Ranking --%>
        <div :if={@flock != []} class="space-y-2">
          <div
            :for={member <- @flock}
            class={[
              "rounded-2xl border p-3 flex items-center gap-3 transition-all",
              if(Map.get(member, :is_me),
                do: "bg-green-50 border-[#4CD964]",
                else: "bg-white border-gray-100"
              )
            ]}
          >
            <%!-- Rank --%>
            <div class={[
              "w-8 h-8 rounded-full flex items-center justify-center text-sm font-extrabold shrink-0",
              rank_badge_class(member.rank)
            ]}>
              {rank_display(member.rank)}
            </div>

            <%!-- Avatar (clickable for non-me) --%>
            <.link
              :if={!Map.get(member, :is_me)}
              navigate={~p"/social/profile/#{member.id}"}
              class={[
                "w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold shrink-0 hover:opacity-80 transition-opacity",
                avatar_class(member)
              ]}
            >
              {String.first(member.display_name || "?")}
            </.link>
            <div
              :if={Map.get(member, :is_me)}
              class="w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold shrink-0 bg-gradient-to-br from-[#4CD964] to-emerald-600 text-white ring-2 ring-green-200"
            >
              {String.first(member.display_name || "?")}
            </div>

            <%!-- Name + tags --%>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-1.5">
                <.link
                  :if={!Map.get(member, :is_me)}
                  navigate={~p"/social/profile/#{member.id}"}
                  class={[
                    "font-bold text-sm truncate hover:underline",
                    follow_name_class(Map.get(member, :follow_state, :none))
                  ]}
                >
                  {member.display_name}
                </.link>
                <p
                  :if={Map.get(member, :is_me)}
                  class="font-bold text-sm truncate text-[#4CD964]"
                >
                  You
                </p>
                <span :if={member.streak >= 3} class="text-xs" title={"#{member.streak} day streak"}>
                  🔥{member.streak}
                </span>
                <span
                  :if={Map.get(member, :follow_state) == :mutual}
                  class="text-xs"
                  title="Friends"
                >
                  ♥
                </span>
              </div>
              <div class="flex gap-1 mt-0.5">
                <span
                  :for={tag <- Enum.take(Map.get(member, :tags, []) -- [:you], 2)}
                  class="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-400"
                >
                  {tag_label(tag)}
                </span>
              </div>
            </div>

            <%!-- Wool indicator --%>
            <div class="shrink-0" title={"Wool level #{member.wool_level}"}>
              <.sheep_inline state={wool_state_from_level(member.wool_level)} />
            </div>

            <%!-- XP --%>
            <div class="text-right shrink-0">
              <p class="text-sm font-extrabold text-gray-900">{member.weekly_xp}</p>
              <p class="text-[10px] text-gray-400">FP</p>
            </div>

            <%!-- Follow button --%>
            <div :if={!Map.get(member, :is_me)} class="shrink-0">
              <button
                :if={Map.get(member, :follow_state) in [:none, :followed_by]}
                phx-click="follow"
                phx-value-id={member.id}
                class="text-xs px-3 py-1 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors"
              >
                + Follow
              </button>
              <button
                :if={Map.get(member, :follow_state) in [:following, :mutual]}
                phx-click="unfollow"
                phx-value-id={member.id}
                class="text-xs px-3 py-1 rounded-full bg-gray-100 text-gray-500 font-bold hover:bg-gray-200 transition-colors"
              >
                {if Map.get(member, :follow_state) == :mutual, do: "Friends ♥", else: "Following"}
              </button>
            </div>
          </div>
        </div>

        <%!-- Empty flock (all filter) --%>
        <div
          :if={@flock == [] and @flock_filter == :all}
          class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
        >
          <.sheep state={:encouraging} size="lg" message="Your flock is forming!" />
          <h3 class="font-extrabold text-gray-900 text-lg mt-4">No flock members yet</h3>
          <p class="text-sm text-gray-500 mt-1">
            As more students at your school and grade level join, your flock will grow!
          </p>
        </div>

        <%!-- League Info --%>
        <div class="bg-white rounded-2xl border border-gray-100 p-4">
          <h3 class="text-xs font-extrabold text-gray-400 uppercase tracking-wider mb-2">
            How Flock works
          </h3>
          <div class="grid grid-cols-3 gap-3 text-center">
            <div>
              <p class="text-lg">🐑</p>
              <p class="text-[10px] text-gray-500 font-bold mt-0.5">
                Matched with<br />similar students
              </p>
            </div>
            <div>
              <p class="text-lg">⚡</p>
              <p class="text-[10px] text-gray-500 font-bold mt-0.5">
                Weekly FP<br />resets every Monday
              </p>
            </div>
            <div>
              <p class="text-lg">🏆</p>
              <p class="text-[10px] text-gray-500 font-bold mt-0.5">Top 3 earn<br />bonus badges</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- ═══ School Tab ═══ --%>
      <div :if={@tab == :school} class="space-y-4 animate-slide-up">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-sm font-extrabold text-gray-900">Your School</h2>
            <p class="text-xs text-gray-500 mt-0.5">
              {length(@school_peers)} students studying with you
            </p>
          </div>
          <.link
            navigate={~p"/social/find"}
            class="text-xs px-3 py-1.5 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors"
          >
            Find Friends
          </.link>
        </div>

        <div
          :if={@school_peers == []}
          class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
        >
          <p class="text-3xl mb-3">🏫</p>
          <h3 class="font-extrabold text-gray-900 text-lg">No classmates found yet</h3>
          <p class="text-sm text-gray-500 mt-1">
            Make sure your school is set in your profile. Invite classmates to join!
          </p>
        </div>

        <div :if={@school_peers != []} class="space-y-2">
          <div
            :for={peer <- @school_peers}
            class="bg-white rounded-2xl border border-gray-100 p-3 flex items-center gap-3"
          >
            <%!-- Avatar --%>
            <.link navigate={~p"/social/profile/#{peer.id}"} class="shrink-0">
              <div class={[
                "w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold hover:opacity-80 transition-opacity",
                peer_avatar_class(peer.follow_state)
              ]}>
                {String.first(peer.display_name || "?")}
              </div>
            </.link>

            <%!-- Info --%>
            <div class="flex-1 min-w-0">
              <.link navigate={~p"/social/profile/#{peer.id}"} class="hover:underline">
                <p class={["font-bold text-sm truncate", follow_name_class(peer.follow_state)]}>
                  {peer.display_name}
                  <span :if={peer.follow_state == :mutual} class="text-xs ml-1">♥</span>
                </p>
              </.link>
              <p class="text-xs text-gray-400 mt-0.5">
                {grade_label(peer.grade)}
                {if peer.streak > 0, do: " · 🔥#{peer.streak} day streak"}
              </p>
            </div>

            <%!-- Weekly XP --%>
            <div class="text-right shrink-0 text-xs text-gray-400">
              <p class="font-bold text-gray-700">{peer.weekly_xp}</p>
              <p>FP/wk</p>
            </div>

            <%!-- Follow button --%>
            <div class="shrink-0">
              <button
                :if={peer.follow_state in [:none, :followed_by]}
                phx-click="follow"
                phx-value-id={peer.id}
                class="text-xs px-3 py-1 rounded-full bg-[#4CD964] text-white font-bold hover:bg-[#3DBF55] transition-colors"
              >
                + Follow
              </button>
              <button
                :if={peer.follow_state in [:following, :mutual]}
                phx-click="unfollow"
                phx-value-id={peer.id}
                class="text-xs px-3 py-1 rounded-full bg-gray-100 text-gray-500 font-bold hover:bg-gray-200 transition-colors"
              >
                {if peer.follow_state == :mutual, do: "Friends ♥", else: "Following"}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- ═══ Shout Outs Tab ═══ --%>
      <div :if={@tab == :shout_outs} class="space-y-4 animate-slide-up">
        <div>
          <h2 class="text-sm font-extrabold text-gray-900">This Week's Stars</h2>
          <p class="text-xs text-gray-500 mt-0.5">
            Weekly spotlight · resets every Monday
          </p>
        </div>

        <div
          :if={@shout_outs == []}
          class="bg-white rounded-2xl border border-gray-100 p-8 text-center"
        >
          <p class="text-3xl mb-3">✨</p>
          <p class="font-extrabold text-gray-900">No shout outs yet this week</p>
          <p class="text-sm text-gray-500 mt-1">
            Be the first to earn one!
          </p>
        </div>

        <div :if={@shout_outs != []} class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <.shout_out_card
            :for={shout_out <- @shout_outs}
            shout_out={shout_out}
            current_user_role_id={@current_user["id"]}
          />
        </div>
      </div>

      <%!-- ═══ Achievements Tab ═══ --%>
      <div :if={@tab == :achievements} class="space-y-4 animate-slide-up">
        <%!-- Stats Overview --%>
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

        <%!-- Earned Achievements --%>
        <div :if={@achievements != []} class="space-y-3">
          <h3 class="text-sm font-extrabold text-gray-900">Earned</h3>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div
              :for={achievement <- @achievements}
              class="bg-white rounded-2xl border border-gray-100 p-4 text-center card-hover"
            >
              <div class="text-3xl mb-2">
                {Achievement.display_info(achievement.achievement_type).emoji}
              </div>
              <p class="text-sm font-bold text-gray-900">
                {Achievement.display_info(achievement.achievement_type).name}
              </p>
              <p class="text-[10px] text-gray-500 mt-0.5">
                {Achievement.display_info(achievement.achievement_type).description}
              </p>
              <p class="text-[10px] text-gray-400 mt-1">
                {Calendar.strftime(achievement.earned_at, "%b %d, %Y")}
              </p>
            </div>
          </div>
        </div>

        <%!-- Locked Achievements --%>
        <div>
          <h3 class="text-sm font-extrabold text-gray-900 mb-3">
            {if @achievements == [], do: "Badges to Earn", else: "Still Locked"}
          </h3>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div
              :for={type <- locked_achievement_types(@achievements)}
              class="bg-gray-50 rounded-2xl border border-gray-100 p-4 text-center opacity-60"
            >
              <div class="text-3xl mb-2 grayscale">{Achievement.display_info(type).emoji}</div>
              <p class="text-sm font-bold text-gray-500">{Achievement.display_info(type).name}</p>
              <p class="text-[10px] text-gray-400 mt-0.5">
                {Achievement.display_info(type).description}
              </p>
              <p class="text-[10px] text-gray-300 mt-1">🔒 Locked</p>
            </div>
          </div>
        </div>

        <%!-- Wool Level Display --%>
        <div class="bg-white rounded-2xl border border-gray-100 p-5">
          <h3 class="text-sm font-extrabold text-gray-900 mb-3">Wool Level</h3>
          <div class="flex items-center gap-4">
            <.sheep
              state={wool_state(@gamification.streak)}
              size="lg"
              wool_level={@gamification.streak.wool_level}
            />
            <div class="flex-1">
              <div class="flex items-center justify-between mb-1">
                <span class="text-sm font-bold text-gray-700">
                  Level {@gamification.streak.wool_level}/10
                </span>
                <span class="text-xs text-gray-500">
                  {wool_description(@gamification.streak.wool_level)}
                </span>
              </div>
              <div class="w-full bg-gray-100 rounded-full h-2.5">
                <div
                  class="bg-gradient-to-r from-amber-200 to-amber-400 h-2.5 rounded-full transition-all"
                  style={"width: #{@gamification.streak.wool_level * 10}%"}
                >
                </div>
              </div>
              <p class="text-xs text-gray-400 mt-1.5">
                Study daily to grow your sheep's wool! Breaks reset the wool.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Shout Out Card Component ─────────────────────────────────────────────

  attr :shout_out, FunSheep.Gamification.ShoutOut, required: true
  attr :current_user_role_id, :string, required: true

  defp shout_out_card(assigns) do
    info = ShoutOut.display_info(assigns.shout_out.category)
    winner_name = get_in(assigns.shout_out.user_role, [Access.key(:display_name)]) || "Anonymous"
    is_me = assigns.shout_out.user_role_id == assigns.current_user_role_id

    assigns =
      assigns
      |> assign(:info, info)
      |> assign(:winner_name, winner_name)
      |> assign(:is_me, is_me)

    ~H"""
    <div class={[
      "rounded-2xl p-4 border transition-all",
      if(@is_me,
        do: "bg-green-50 border-[#4CD964] ring-2 ring-[#4CD964] animate-pulse-once",
        else: "bg-white border-gray-100"
      )
    ]}>
      <div class="flex items-center gap-2 mb-3">
        <span class="text-2xl">{@info.icon}</span>
        <span class="text-xs font-extrabold text-gray-500 uppercase tracking-wider">
          {@info.label}
        </span>
      </div>

      <p class={[
        "font-extrabold text-base truncate",
        if(@is_me, do: "text-[#4CD964]", else: "text-gray-900")
      ]}>
        {if @is_me, do: "You", else: @winner_name}
      </p>

      <p class="text-sm text-gray-500 mt-0.5">
        <span class="font-extrabold text-gray-700">{@shout_out.metric_value}</span>
        {@info.unit}
      </p>

      <div :if={@is_me} class="mt-2">
        <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-bold bg-[#4CD964] text-white shadow-sm">
          That's you! 🎉
        </span>
      </div>
    </div>
    """
  end

  # ── Podium Component ─────────────────────────────────────────────────────

  defp podium(assigns) do
    top3 = Enum.take(assigns.flock, 3)

    ordered =
      case top3 do
        [first, second, third] -> [second, first, third]
        other -> other
      end

    assigns = assign(assigns, :podium_members, ordered)

    ~H"""
    <div class="flex items-end justify-center gap-3 py-4">
      <div
        :for={{member, _visual_idx} <- Enum.with_index(@podium_members)}
        class="flex flex-col items-center"
      >
        <div :if={member.rank == 1} class="text-2xl mb-1 animate-float">👑</div>

        <.link :if={!Map.get(member, :is_me)} navigate={~p"/social/profile/#{member.id}"}>
          <div class={[
            "rounded-full flex items-center justify-center font-bold mb-2 shadow-lg hover:opacity-80 transition-opacity",
            podium_avatar_class(member.rank)
          ]}>
            {String.first(member.display_name || "?")}
          </div>
        </.link>
        <div
          :if={Map.get(member, :is_me)}
          class={[
            "rounded-full flex items-center justify-center font-bold mb-2 shadow-lg",
            podium_avatar_class(member.rank)
          ]}
        >
          {String.first(member.display_name || "?")}
        </div>

        <p class="text-xs font-bold text-gray-700 truncate max-w-[80px] text-center">
          {if Map.get(member, :is_me), do: "You", else: member.display_name}
        </p>

        <p class="text-xs font-extrabold text-gray-900 mt-0.5">{member.weekly_xp} FP</p>

        <div class={[
          "w-20 rounded-t-xl mt-2 flex items-center justify-center",
          podium_block_class(member.rank)
        ]}>
          <span class="text-lg font-extrabold text-white">{member.rank}</span>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp refresh_social(socket, user_role_id) do
    filter = socket.assigns.flock_filter
    {flock, my_rank, flock_size} = Social.flock_with_social(user_role_id, filter: filter)
    school_peers = Social.school_peers(user_role_id, limit: 50)

    assign(socket,
      flock: flock,
      my_rank: my_rank,
      flock_size: flock_size,
      school_peers: school_peers
    )
  end

  defp default_gamification do
    %{
      streak: %{current_streak: 0, longest_streak: 0, wool_level: 0, last_activity_date: nil},
      total_xp: 0,
      xp_today: 0,
      achievement_count: 0,
      sheep_state: :encouraging
    }
  end

  defp tab_class(true),
    do:
      "px-4 py-2 rounded-full text-sm font-bold bg-[#4CD964] text-white shadow-md transition-all"

  defp tab_class(false),
    do:
      "px-4 py-2 rounded-full text-sm font-bold bg-gray-100 text-gray-600 hover:bg-gray-200 transition-all"

  defp filter_class(true),
    do: "px-3 py-1.5 rounded-full text-xs font-bold bg-gray-800 text-white transition-all"

  defp filter_class(false),
    do:
      "px-3 py-1.5 rounded-full text-xs font-bold bg-gray-100 text-gray-500 hover:bg-gray-200 transition-all"

  defp week_start do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    Date.add(today, -(day_of_week - 1))
  end

  defp league_name(rank) when rank <= 3, do: "Gold"
  defp league_name(rank) when rank <= 10, do: "Silver"
  defp league_name(_), do: "Bronze"

  defp rank_message(1, _), do: "You're leading the flock! 🎉"
  defp rank_message(2, _), do: "Almost there — 1 spot from the top!"
  defp rank_message(3, _), do: "On the podium! Keep pushing!"
  defp rank_message(rank, size) when rank <= div(size, 3), do: "Top third! You're doing great!"
  defp rank_message(_, _), do: "Every FP counts — keep studying!"

  defp find_my_xp(flock) do
    case Enum.find(flock, &Map.get(&1, :is_me)) do
      nil -> 0
      me -> me.weekly_xp
    end
  end

  defp rank_display(1), do: "🥇"
  defp rank_display(2), do: "🥈"
  defp rank_display(3), do: "🥉"
  defp rank_display(n), do: to_string(n)

  defp rank_badge_class(1), do: "bg-amber-100 text-amber-600"
  defp rank_badge_class(2), do: "bg-gray-100 text-gray-500"
  defp rank_badge_class(3), do: "bg-orange-100 text-orange-500"
  defp rank_badge_class(_), do: "bg-gray-50 text-gray-400"

  defp podium_avatar_class(1),
    do:
      "w-16 h-16 bg-gradient-to-br from-amber-400 to-yellow-500 text-white text-xl ring-4 ring-amber-200"

  defp podium_avatar_class(2),
    do:
      "w-12 h-12 bg-gradient-to-br from-gray-300 to-gray-400 text-white text-lg ring-2 ring-gray-200"

  defp podium_avatar_class(_),
    do:
      "w-12 h-12 bg-gradient-to-br from-orange-300 to-orange-400 text-white text-lg ring-2 ring-orange-200"

  defp podium_block_class(1), do: "bg-gradient-to-b from-amber-400 to-amber-500 h-20"
  defp podium_block_class(2), do: "bg-gradient-to-b from-gray-300 to-gray-400 h-14"
  defp podium_block_class(_), do: "bg-gradient-to-b from-orange-300 to-orange-400 h-10"

  defp tag_label(:school), do: "🏫 School"
  defp tag_label(:course), do: "📚 Course"
  defp tag_label(:subject), do: "📖 Subject"
  defp tag_label(:grade), do: "🎓 Grade"
  defp tag_label(:gender), do: "👥 Peers"
  defp tag_label(_), do: ""

  defp wool_state_from_level(0), do: :sheared
  defp wool_state_from_level(level) when level >= 8, do: :fluffy
  defp wool_state_from_level(_), do: :studying

  defp follow_name_class(:mutual), do: "text-[#4CD964]"
  defp follow_name_class(:following), do: "text-blue-600"
  defp follow_name_class(_), do: "text-gray-900"

  defp avatar_class(%{follow_state: :mutual}),
    do: "bg-gradient-to-br from-[#4CD964] to-emerald-600 text-white ring-2 ring-green-200"

  defp avatar_class(%{follow_state: :following}),
    do: "bg-blue-100 text-blue-600"

  defp avatar_class(_), do: "bg-gray-100 text-gray-600"

  defp peer_avatar_class(:mutual),
    do: "bg-gradient-to-br from-[#4CD964] to-emerald-600 text-white ring-2 ring-green-200"

  defp peer_avatar_class(:following), do: "bg-blue-100 text-blue-600"
  defp peer_avatar_class(:followed_by), do: "bg-purple-100 text-purple-600"
  defp peer_avatar_class(_), do: "bg-gray-100 text-gray-600"

  defp grade_label(nil), do: "Student"
  defp grade_label(g), do: "Grade #{g}"

  @all_types ~w(
    golden_fleece first_assessment first_practice
    streak_3 streak_7 streak_14 streak_30 streak_100
    topic_mastery chapter_mastery speed_demon perfect_score
    night_owl early_bird comeback_kid
    first_follow first_follower flock_starter shepherd
    lead_shepherd flock_builder study_buddy mutual_10
  )

  defp locked_achievement_types(earned) do
    earned_types = MapSet.new(earned, & &1.achievement_type)
    Enum.reject(@all_types, &MapSet.member?(earned_types, &1))
  end

  defp wool_state(%{wool_level: 0}), do: :sheared
  defp wool_state(%{wool_level: level}) when level >= 8, do: :fluffy
  defp wool_state(_), do: :studying

  defp wool_description(0), do: "Bare! Start a streak"
  defp wool_description(level) when level <= 2, do: "Thin wool"
  defp wool_description(level) when level <= 4, do: "Getting there"
  defp wool_description(level) when level <= 6, do: "Nice and warm"
  defp wool_description(level) when level <= 8, do: "Extra fluffy!"
  defp wool_description(_), do: "Maximum floof!"
end
