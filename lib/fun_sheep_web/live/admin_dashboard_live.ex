defmodule FunSheepWeb.AdminDashboardLive do
  use FunSheepWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    review_count = FunSheep.Questions.count_questions_needing_review()
    {:ok, assign(socket, page_title: "Admin Dashboard", review_count: review_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Admin Dashboard</h1>
      <p class="text-[#8E8E93] mt-2">Welcome back, {@current_user["display_name"]}!</p>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mt-8">
        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Users</h3>
            <.icon name="hero-users" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#4CD964]">0</p>
          <p class="text-sm text-[#8E8E93] mt-1">Total users</p>
        </div>

        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Schools</h3>
            <.icon name="hero-building-library" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#4CD964]">0</p>
          <p class="text-sm text-[#8E8E93] mt-1">Registered schools</p>
        </div>

        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Courses</h3>
            <.icon name="hero-book-open" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#4CD964]">0</p>
          <p class="text-sm text-[#8E8E93] mt-1">Active courses</p>
        </div>

        <.link
          navigate={~p"/admin/questions/review"}
          class="bg-white rounded-2xl shadow-md p-6 hover:shadow-lg transition-shadow block"
        >
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">Question Review</h3>
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class={[
            "text-3xl font-bold",
            if(@review_count > 0, do: "text-[#FFCC00]", else: "text-[#4CD964]")
          ]}>
            {@review_count}
          </p>
          <p class="text-sm text-[#8E8E93] mt-1">Flagged for review</p>
        </.link>

        <div class="bg-white rounded-2xl shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-[#1C1C1E]">System</h3>
            <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-[#8E8E93]" />
          </div>
          <p class="text-3xl font-bold text-[#4CD964]">OK</p>
          <p class="text-sm text-[#8E8E93] mt-1">System status</p>
        </div>
      </div>
    </div>
    """
  end
end
