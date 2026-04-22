defmodule FunSheepWeb.BillingComponents do
  @moduledoc """
  Shared billing UI components for test limit enforcement.

  Flow A surfaces (§4.1, §4.3, §4.4, §4.5, §4.6.2):

    * `usage_meter/1` — ambient pill + dashboard card on the student
      dashboard. Maps `FunSheep.Billing.usage_state/1` to cheerful copy
      at each threshold.
    * `ask_card/1` — the 85% call-to-action that opens the request
      modal.
    * `waiting_card/1` — shown once a request has been sent, awaiting
      the guardian's decision.
    * `parent_request_card/1` — shown on the parent dashboard when one
      or more pending requests are addressed to them.

  All copy is frame-positive (§3.3, §4.1): we avoid "limit," "quota,"
  "paywall" and never use fear framing.
  """

  use Phoenix.Component

  @doc """
  Usage meter shown on the student's app bar (variant `:pill`) and
  dashboard (variant `:card`). Maps `usage_state/1` to the §4.1 copy.
  """
  attr :state, :atom,
    required: true,
    values: [:fresh, :warming, :nudge, :ask, :hardwall, :paid, :not_applicable]

  attr :used, :integer, default: 0
  attr :limit, :integer, default: 20
  attr :remaining, :integer, default: 20
  attr :resets_at, :any, default: nil
  attr :variant, :atom, default: :pill, values: [:pill, :card]

  def usage_meter(%{state: :not_applicable} = assigns), do: ~H""
  def usage_meter(%{state: :paid, variant: :pill} = assigns), do: paid_pill(assigns)
  def usage_meter(%{variant: :pill} = assigns), do: meter_pill(assigns)
  def usage_meter(%{variant: :card} = assigns), do: meter_card(assigns)

  defp paid_pill(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 px-3 py-1 bg-[#E8F8EB] dark:bg-[#4CD964]/20 text-[#1C1C1E] dark:text-white text-sm font-medium rounded-full">
      <span aria-hidden="true">💚</span>
      <span>Unlimited practice</span>
    </span>
    """
  end

  defp meter_pill(assigns) do
    {emoji, text} = pill_copy(assigns.state, assigns.remaining)

    assigns = assign(assigns, emoji: emoji, text: text)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-3 py-1 text-sm font-medium rounded-full",
      pill_tone(@state)
    ]}>
      <span aria-hidden="true">{@emoji}</span>
      <span>{@text}</span>
    </span>
    """
  end

  defp meter_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-[#1C1C1E] dark:text-white">
          Your weekly practice
        </h3>
        <.usage_meter
          state={@state}
          used={@used}
          limit={@limit}
          remaining={@remaining}
          variant={:pill}
        />
      </div>

      <div class="h-2 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-full overflow-hidden mb-3">
        <div
          class={[
            "h-full rounded-full transition-all",
            bar_tone(@state)
          ]}
          style={"width: #{progress_pct(@used, @limit)}%"}
          aria-hidden="true"
        >
        </div>
      </div>

      <p class="text-sm text-[#8E8E93]">
        {card_subtext(@state, @used, @limit, @resets_at)}
      </p>
    </div>
    """
  end

  # §4.1 pill copy table
  defp pill_copy(:fresh, remaining), do: {"🐑", "#{remaining} free practice left this week"}
  defp pill_copy(:warming, remaining), do: {"🐑", "#{remaining} free practice left — nice streak"}
  defp pill_copy(:nudge, remaining), do: {"🐑", "#{remaining} left this week — great momentum"}
  defp pill_copy(:ask, remaining), do: {"🐑", "#{remaining} left — ask a grown-up for more?"}
  defp pill_copy(:hardwall, _), do: {"🌿", "Weekly practice complete — unlock more?"}
  defp pill_copy(_, _), do: {"🐑", "Free practice"}

  # Tone stays positive throughout — never red/warning until hardwall,
  # and even there stays encouraging (green-tinted). §4.1.
  defp pill_tone(:fresh), do: "bg-[#E8F8EB] text-[#1C1C1E] dark:bg-[#4CD964]/15 dark:text-white"
  defp pill_tone(:warming), do: "bg-[#E8F8EB] text-[#1C1C1E] dark:bg-[#4CD964]/15 dark:text-white"
  defp pill_tone(:nudge), do: "bg-[#FFF9E8] text-[#1C1C1E] dark:bg-[#FFCC00]/15 dark:text-white"
  defp pill_tone(:ask), do: "bg-[#FFF9E8] text-[#1C1C1E] dark:bg-[#FFCC00]/20 dark:text-white"

  defp pill_tone(:hardwall),
    do: "bg-[#E8F8EB] text-[#1C1C1E] dark:bg-[#4CD964]/25 dark:text-white"

  defp pill_tone(_), do: "bg-[#F5F5F7] text-[#1C1C1E] dark:bg-[#2C2C2E] dark:text-white"

  defp bar_tone(s) when s in [:fresh, :warming], do: "bg-[#4CD964]"
  defp bar_tone(:nudge), do: "bg-[#4CD964]"
  defp bar_tone(:ask), do: "bg-[#FFCC00]"
  defp bar_tone(:hardwall), do: "bg-[#4CD964]"
  defp bar_tone(_), do: "bg-[#4CD964]"

  defp progress_pct(_used, limit) when limit <= 0, do: 0
  defp progress_pct(used, limit), do: min(100, round(used / limit * 100))

  defp card_subtext(:hardwall, _used, limit, resets_at) do
    "You've finished your #{limit} free practice questions this week. Your next slot opens #{format_reset(resets_at)}."
  end

  defp card_subtext(_, used, limit, resets_at) do
    "#{used} of #{limit} this week · resets #{format_reset(resets_at)}"
  end

  defp format_reset(nil), do: "soon"

  defp format_reset(%DateTime{} = dt) do
    case DateTime.diff(dt, DateTime.utc_now(), :second) do
      s when s <= 0 -> "any moment now"
      s when s < 3600 -> "in #{div(s, 60)} minutes"
      s when s < 86_400 -> "in #{div(s, 3600)} hours"
      s -> "in #{div(s, 86_400)} days"
    end
  end

  defp format_reset(_), do: "soon"

  @doc """
  The 85% Ask card. §4.3.

  Rendered only when `state == :ask` AND the student has no pending
  request AND isn't already paid. Caller is responsible for gating.
  """
  attr :rest, :global
  attr :open_event, :string, default: "open_ask_modal"
  attr :target, :any, default: nil

  def ask_card(assigns) do
    ~H"""
    <div
      class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 border border-[#E8F8EB] dark:border-[#4CD964]/30"
      {@rest}
    >
      <h3 class="text-xl font-bold text-[#1C1C1E] dark:text-white mb-2">
        Almost at your weekly free practice 🦁
      </h3>
      <p class="text-[#1C1C1E] dark:text-white mb-2">
        You're clearly into this. Want unlimited practice for the rest of the term?
      </p>
      <p class="text-sm text-[#8E8E93] mb-4">
        It takes one tap to ask your parent — and research shows <em>parents love it</em>
        when their kid asks for more practice.
      </p>
      <p class="text-xs text-[#8E8E93] italic mb-5">
        (They really do. This is one of those rare parent-wins. Use it wisely.)
      </p>

      <button
        type="button"
        phx-click={@open_event}
        phx-target={@target}
        class="w-full sm:w-auto bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors focus:outline-none focus:ring-2 focus:ring-[#4CD964] focus:ring-offset-2"
      >
        💚 Ask a grown-up
      </button>
    </div>
    """
  end

  @doc """
  Waiting card shown after the student's request has been sent. §4.5.
  """
  attr :guardian_name, :string, default: "your grown-up"
  attr :sent_at, :any, required: true
  attr :reminder_sent, :boolean, default: false
  attr :can_remind, :boolean, default: false
  attr :target, :any, default: nil

  def waiting_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6">
      <h3 class="text-lg font-semibold text-[#1C1C1E] dark:text-white mb-1">
        Request sent to {@guardian_name} 💌
      </h3>
      <p class="text-sm text-[#8E8E93] mb-4">
        Sent {relative_time(@sent_at)} · typically answered within a few hours.
      </p>
      <p class="text-sm text-[#1C1C1E] dark:text-white mb-4">
        You can keep reviewing what you've already done while you wait.
      </p>

      <div :if={@can_remind and not @reminder_sent}>
        <button
          type="button"
          phx-click="send_reminder"
          phx-target={@target}
          class="text-sm text-[#007AFF] hover:underline font-medium"
        >
          Send a gentle reminder
        </button>
      </div>

      <p :if={@reminder_sent} class="text-xs text-[#8E8E93]">
        Reminder sent — they'll see it next time they check.
      </p>
    </div>
    """
  end

  @doc """
  Card shown on the parent dashboard when the parent has at least one
  pending request from a linked student. §4.6.2, §8.3.
  """
  attr :requests, :list, required: true
  attr :target, :any, default: nil

  def parent_request_card(%{requests: []} = assigns), do: ~H""

  def parent_request_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 border-2 border-[#4CD964]/40">
      <div class="flex items-start gap-3 mb-4">
        <div class="text-2xl" aria-hidden="true">💚</div>
        <div>
          <h3 class="text-lg font-semibold text-[#1C1C1E] dark:text-white">
            {ask_headline(@requests)}
          </h3>
          <p class="text-sm text-[#8E8E93]">
            {ask_subhead(@requests)}
          </p>
        </div>
      </div>

      <ul class="space-y-4 mb-5">
        <li
          :for={req <- @requests}
          class="border-t border-[#E5E5EA] dark:border-[#3A3A3C] pt-4 first:border-t-0 first:pt-0"
        >
          <p class="text-sm font-medium text-[#1C1C1E] dark:text-white">
            {req.student.display_name}:
          </p>
          <p class="text-sm text-[#1C1C1E] dark:text-white italic mb-2">
            "{reason_text(req)}"
          </p>
          <p class="text-xs text-[#8E8E93] mb-3">
            {evidence_line(req.metadata)}
          </p>
          <div class="flex flex-wrap gap-2">
            <.link
              navigate={"/subscription?request=#{req.id}"}
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-5 py-2 rounded-full shadow-md transition-colors text-sm"
            >
              Unlock unlimited for {req.student.display_name}
            </.link>
            <button
              type="button"
              phx-click="decline_request"
              phx-target={@target}
              phx-value-id={req.id}
              class="px-5 py-2 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-[#1C1C1E] dark:text-white font-medium hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors text-sm"
            >
              Not right now
            </button>
          </div>
        </li>
      </ul>

      <p class="text-xs text-[#8E8E93]">
        You can always say not right now — they'll be told kindly.
      </p>
    </div>
    """
  end

  defp ask_headline([_]), do: "Your child asked for more practice"
  defp ask_headline(reqs), do: "#{length(reqs)} requests from your kids"

  defp ask_subhead([_]), do: "Here's the evidence they're really using it."
  defp ask_subhead(_), do: "Review each request and unlock or decline individually."

  defp reason_text(%{reason_code: :upcoming_test, metadata: %{"upcoming_test" => %{"name" => n}}})
       when is_binary(n),
       do: "I want to ace my #{n}"

  defp reason_text(%{reason_code: :upcoming_test}), do: "I want to ace my upcoming test"

  defp reason_text(%{reason_code: :weak_topic}),
    do: "I'm working on my weakest topic and want to get it right"

  defp reason_text(%{reason_code: :streak}), do: "I'm on a streak and I want to keep going"

  defp reason_text(%{reason_code: :other, reason_text: t}) when is_binary(t) and t != "", do: t
  defp reason_text(_), do: "I want more practice this week"

  defp evidence_line(%{"streak_days" => s, "weekly_minutes" => m, "accuracy_pct" => a}) do
    "#{s}-day streak · #{m} min this week · #{a}% accuracy"
  end

  defp evidence_line(_), do: ""

  defp relative_time(nil), do: "just now"

  defp relative_time(%DateTime{} = dt) do
    case DateTime.diff(DateTime.utc_now(), dt, :second) do
      s when s < 60 -> "just now"
      s when s < 3600 -> "#{div(s, 60)} minutes ago"
      s when s < 86_400 -> "#{div(s, 3600)} hours ago"
      s -> "#{div(s, 86_400)} days ago"
    end
  end

  defp relative_time(_), do: "recently"

  @doc """
  The request-builder modal (§4.4). ≤2 taps to send.

  The caller hosts `:show`, `:guardians`, and `:selected_reason` state
  and handles the `close_ask_modal`, `select_reason`, and
  `submit_request` events.
  """
  attr :show, :boolean, default: false
  attr :guardians, :list, default: []
  attr :selected_guardian_id, :any, default: nil
  attr :selected_reason, :atom, default: nil
  attr :reason_text, :string, default: ""
  attr :error, :string, default: nil
  attr :target, :any, default: nil

  def ask_modal(assigns) do
    ~H"""
    <div :if={@show} class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
      <form
        phx-submit="submit_request"
        phx-target={@target}
        class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-xl max-w-md w-full p-6 sm:p-8"
        role="dialog"
        aria-labelledby="ask-modal-title"
      >
        <div class="flex items-start justify-between mb-4">
          <h2 id="ask-modal-title" class="text-xl font-bold text-[#1C1C1E] dark:text-white">
            Ask for unlimited practice
          </h2>
          <button
            type="button"
            phx-click="close_ask_modal"
            phx-target={@target}
            class="text-[#8E8E93] hover:text-[#1C1C1E] dark:hover:text-white p-1 rounded-lg"
            aria-label="Close"
          >
            <svg
              class="w-5 h-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div :if={length(@guardians) > 1} class="mb-4">
          <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mb-2">
            Pick a grown-up
          </p>
          <div class="space-y-2">
            <label
              :for={g <- @guardians}
              class="flex items-center gap-3 p-3 rounded-xl border border-[#E5E5EA] dark:border-[#3A3A3C] cursor-pointer hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E]"
            >
              <input
                type="radio"
                name="guardian_id"
                value={g.id}
                checked={@selected_guardian_id == g.id}
                class="w-5 h-5 accent-[#4CD964]"
              />
              <span class="text-[#1C1C1E] dark:text-white">{g.display_name}</span>
            </label>
          </div>
        </div>

        <input
          :if={length(@guardians) <= 1}
          type="hidden"
          name="guardian_id"
          value={List.first(@guardians) && List.first(@guardians).id}
        />

        <div class="mb-4">
          <p class="text-sm font-medium text-[#1C1C1E] dark:text-white mb-2">
            Pick a reason
          </p>
          <div class="space-y-2">
            <label
              :for={{code, label} <- reason_options()}
              class="flex items-center gap-3 p-3 rounded-xl border border-[#E5E5EA] dark:border-[#3A3A3C] cursor-pointer hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E]"
            >
              <input
                type="radio"
                name="reason_code"
                value={code}
                phx-click="select_reason"
                phx-target={@target}
                phx-value-code={code}
                checked={@selected_reason == code}
                class="w-5 h-5 accent-[#4CD964]"
              />
              <span class="text-[#1C1C1E] dark:text-white text-sm">{label}</span>
            </label>
          </div>
        </div>

        <div :if={@selected_reason == :other} class="mb-4">
          <label class="block text-sm font-medium text-[#1C1C1E] dark:text-white mb-2">
            What do you want to say?
          </label>
          <input
            type="text"
            name="reason_text"
            value={@reason_text}
            maxlength="140"
            placeholder="Tell your grown-up (max 140 characters)"
            class="w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          />
        </div>

        <p :if={@error} class="text-sm text-[#FF3B30] mb-3">
          {@error}
        </p>

        <p class="text-xs text-[#8E8E93] italic mb-4">
          Your parents will love this. Parents literally post on social media when their kid
          asks for more practice. Hit send. 🦁💚
        </p>

        <button
          type="submit"
          disabled={is_nil(@selected_reason)}
          class="w-full bg-[#4CD964] hover:bg-[#3DBF55] disabled:bg-[#E5E5EA] disabled:text-[#8E8E93] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors focus:outline-none focus:ring-2 focus:ring-[#4CD964] focus:ring-offset-2"
        >
          Send
        </button>

        <p class="text-xs text-[#8E8E93] mt-3 text-center">
          Your grown-up will get an email + a notification in the app.
        </p>
      </form>
    </div>
    """
  end

  defp reason_options do
    [
      {"upcoming_test", "I want to ace my upcoming test"},
      {"weak_topic", "I'm working on my weakest topic"},
      {"streak", "I'm on a streak and want to keep going"},
      {"other", "Other (in my own words)"}
    ]
  end

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
        <button
          type="button"
          onclick={"var r = document.referrer; if (r && new URL(r).origin === location.origin && r !== location.href) { history.back() } else { location.href = '/courses/#{@course_id}' }"}
          class="px-6 py-2 rounded-full border border-[#E5E5EA] dark:border-[#3A3A3C] text-[#1C1C1E] dark:text-white font-medium hover:bg-[#F5F5F7] dark:hover:bg-[#1C1C1E] transition-colors cursor-pointer"
        >
          Back
        </button>
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
