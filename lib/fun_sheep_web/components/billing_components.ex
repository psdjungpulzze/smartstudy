defmodule FunSheepWeb.BillingComponents do
  @moduledoc """
  Shared billing UI components for test limit enforcement.
  """

  use Phoenix.Component

  attr :course_id, :string, required: true
  attr :course_name, :string, required: true
  attr :stats, :map, required: true

  def billing_wall(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 sm:p-8 text-center">
      <div class="w-16 h-16 bg-[#FFCC00]/10 rounded-full flex items-center justify-center mx-auto mb-4">
        <svg
          class="w-8 h-8 text-[#FFCC00]"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"
          />
        </svg>
      </div>

      <h2 class="text-xl font-bold text-[#1C1C1E] dark:text-white mb-2">Free Test Limit Reached</h2>

      <p class="text-[#8E8E93] mb-6 max-w-md mx-auto">
        You've used all {@stats.weekly_limit} free tests this week.
        Upgrade to get unlimited tests, or wait until your weekly limit resets.
      </p>

      <div class="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
        <.link
          navigate="/subscription"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Upgrade Now
        </.link>
        <.link
          navigate={"/courses/#{@course_id}"}
          class="px-6 py-2 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-[#1C1C1E] dark:text-white font-medium hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors"
        >
          Back to Course
        </.link>
      </div>

      <div class="bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl p-4 max-w-sm mx-auto">
        <div class="grid grid-cols-2 gap-4 text-sm">
          <div>
            <div class="font-medium text-[#1C1C1E] dark:text-white">{@stats.total_tests}</div>
            <div class="text-[#8E8E93]">Total tests taken</div>
          </div>
          <div>
            <div class="font-medium text-[#1C1C1E] dark:text-white">
              {@stats.weekly_tests}/{@stats.weekly_limit}
            </div>
            <div class="text-[#8E8E93]">This week</div>
          </div>
        </div>
        <div class="mt-3 pt-3 border-t border-[#E5E5EA] dark:border-[#3A3A3C] text-xs text-[#8E8E93]">
          Resets {Calendar.strftime(@stats.resets_at, "%B %d")} &bull; Practice mode is always free
        </div>
      </div>
    </div>
    """
  end
end
