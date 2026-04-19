defmodule FunSheepWeb.ReviewLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.SheepMascot

  alias FunSheep.Engagement.{SpacedRepetition, StudySessions}
  alias FunSheep.Gamification

  @batch_size 5
  @xp_per_card 10

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["id"]

    cards = SpacedRepetition.next_review_batch(user_role_id, course_id, @batch_size)

    socket =
      if cards == [] do
        review_stats = SpacedRepetition.review_stats(user_role_id)

        assign(socket,
          page_title: "Review",
          course_id: course_id,
          cards: [],
          current_card: nil,
          card_index: 0,
          total_cards: 0,
          show_answer: false,
          session_id: nil,
          completed: false,
          cards_reviewed: 0,
          xp_earned: 0,
          review_stats: review_stats
        )
      else
        session =
          StudySessions.start_session(user_role_id, "review", %{course_id: course_id})

        session_id =
          case session do
            {:ok, s} -> s.id
            _ -> nil
          end

        assign(socket,
          page_title: "Review",
          course_id: course_id,
          cards: cards,
          current_card: List.first(cards),
          card_index: 0,
          total_cards: length(cards),
          show_answer: false,
          session_id: session_id,
          completed: false,
          cards_reviewed: 0,
          xp_earned: 0,
          review_stats: nil
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("show_answer", _params, socket) do
    {:noreply, assign(socket, show_answer: true)}
  end

  def handle_event("rate", %{"quality" => quality_str}, socket) do
    quality = String.to_integer(quality_str)
    card = socket.assigns.current_card
    user_role_id = socket.assigns.current_user["id"]

    # Record the review
    SpacedRepetition.review_card(card.id, quality)

    # Award XP
    Gamification.award_xp(user_role_id, @xp_per_card, "review")
    Gamification.record_activity(user_role_id)

    cards_reviewed = socket.assigns.cards_reviewed + 1
    xp_earned = socket.assigns.xp_earned + @xp_per_card
    next_index = socket.assigns.card_index + 1

    socket =
      if next_index >= socket.assigns.total_cards do
        # All cards reviewed - complete session
        if socket.assigns.session_id do
          StudySessions.complete_session(socket.assigns.session_id, %{
            cards_reviewed: cards_reviewed,
            xp_earned: xp_earned
          })
        end

        review_stats = SpacedRepetition.review_stats(user_role_id)
        due_count = SpacedRepetition.due_card_count(user_role_id, socket.assigns.course_id)

        assign(socket,
          completed: true,
          cards_reviewed: cards_reviewed,
          xp_earned: xp_earned,
          current_card: nil,
          show_answer: false,
          review_stats: review_stats,
          remaining_due: due_count
        )
      else
        assign(socket,
          card_index: next_index,
          current_card: Enum.at(socket.assigns.cards, next_index),
          show_answer: false,
          cards_reviewed: cards_reviewed,
          xp_earned: xp_earned
        )
      end

    {:noreply, socket}
  end

  defp difficulty_badge_class(difficulty) do
    case difficulty do
      :easy -> "bg-[#E8F8EB] text-[#4CD964]"
      :medium -> "bg-yellow-100 text-yellow-700"
      :hard -> "bg-red-100 text-[#FF3B30]"
      _ -> "bg-gray-100 text-gray-600"
    end
  end

  defp difficulty_label(difficulty) do
    case difficulty do
      :easy -> "Easy"
      :medium -> "Medium"
      :hard -> "Hard"
      _ -> to_string(difficulty)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto px-4">
      <%!-- Header --%>
      <div class="flex items-center gap-4 mb-6">
        <.link
          navigate={~p"/dashboard"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-6 h-6" />
        </.link>
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Just This</h1>
          <p class="text-sm text-[#8E8E93]">Quick spaced repetition review</p>
        </div>
      </div>

      <%!-- Empty state: no cards due --%>
      <div
        :if={@total_cards == 0 and not @completed}
        class="bg-white rounded-2xl shadow-md p-8 text-center"
      >
        <div class="flex justify-center mb-4">
          <.sheep state={:celebrating} size="lg" />
        </div>
        <h2 class="text-xl font-bold text-[#1C1C1E] mb-2">All caught up!</h2>
        <p class="text-[#8E8E93] mb-6">
          No cards are due for review right now. Come back later when your next batch is ready.
        </p>
        <.link
          navigate={~p"/dashboard"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors inline-block"
        >
          Back to Dashboard
        </.link>
      </div>

      <%!-- Active review card --%>
      <div :if={@current_card && not @completed}>
        <%!-- Progress dots --%>
        <div class="flex justify-center gap-2 mb-6">
          <div
            :for={i <- 0..(@total_cards - 1)}
            class={[
              "w-3 h-3 rounded-full transition-colors",
              cond do
                i < @card_index -> "bg-[#4CD964]"
                i == @card_index -> "bg-[#1C1C1E]"
                true -> "bg-[#E5E5EA]"
              end
            ]}
          />
        </div>

        <%!-- Card --%>
        <div class="bg-white rounded-2xl shadow-md p-6 sm:p-8">
          <%!-- Card metadata --%>
          <div class="flex items-center justify-between mb-4">
            <p class="text-xs text-[#8E8E93]">
              Card {@card_index + 1} of {@total_cards}
              <span :if={@current_card.question.chapter}>
                &middot; {@current_card.question.chapter.name}
              </span>
            </p>
            <span class={"px-3 py-1 rounded-full text-xs font-medium #{difficulty_badge_class(@current_card.question.difficulty)}"}>
              {difficulty_label(@current_card.question.difficulty)}
            </span>
          </div>

          <%!-- Question --%>
          <div class="mb-6">
            <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed">
              {@current_card.question.content}
            </p>

            <%!-- MCQ options (read-only display) --%>
            <div
              :if={
                @current_card.question.question_type == :multiple_choice &&
                  @current_card.question.options
              }
              class="mt-4 space-y-2"
            >
              <div
                :for={
                  {key, value} <-
                    Enum.sort_by(@current_card.question.options || %{}, fn {k, _} -> k end)
                }
                class="p-3 rounded-xl bg-[#F5F5F7] text-sm text-[#1C1C1E]"
              >
                <span class="font-medium">{key}.</span>
                <span class="ml-2">{value}</span>
              </div>
            </div>
          </div>

          <%!-- Show Answer button --%>
          <div :if={not @show_answer} class="flex justify-center">
            <button
              phx-click="show_answer"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors w-full sm:w-auto"
            >
              Show Answer
            </button>
          </div>

          <%!-- Answer revealed --%>
          <div :if={@show_answer}>
            <div class="bg-[#E8F8EB] rounded-xl p-4 mb-6">
              <p class="text-xs font-medium text-[#4CD964] uppercase tracking-wider mb-1">Answer</p>
              <p class="text-[#1C1C1E] font-medium">{@current_card.question.answer}</p>
            </div>

            <%!-- Rating buttons --%>
            <p class="text-sm text-[#8E8E93] text-center mb-3">How well did you remember?</p>
            <div class="grid grid-cols-3 gap-3">
              <button
                phx-click="rate"
                phx-value-quality="1"
                class="flex flex-col items-center gap-1 px-4 py-3 rounded-2xl border-2 border-[#FF3B30] bg-red-50 hover:bg-red-100 transition-colors"
              >
                <span class="text-lg">😓</span>
                <span class="text-sm font-medium text-[#FF3B30]">Again</span>
                <span class="text-[10px] text-[#8E8E93]">Didn't know</span>
              </button>

              <button
                phx-click="rate"
                phx-value-quality="3"
                class="flex flex-col items-center gap-1 px-4 py-3 rounded-2xl border-2 border-amber-400 bg-amber-50 hover:bg-amber-100 transition-colors"
              >
                <span class="text-lg">🤔</span>
                <span class="text-sm font-medium text-amber-600">Good</span>
                <span class="text-[10px] text-[#8E8E93]">With effort</span>
              </button>

              <button
                phx-click="rate"
                phx-value-quality="5"
                class="flex flex-col items-center gap-1 px-4 py-3 rounded-2xl border-2 border-[#4CD964] bg-[#E8F8EB] hover:bg-green-100 transition-colors"
              >
                <span class="text-lg">😎</span>
                <span class="text-sm font-medium text-[#4CD964]">Easy</span>
                <span class="text-[10px] text-[#8E8E93]">Knew it!</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Completion receipt --%>
      <div :if={@completed} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <div class="flex justify-center mb-4">
          <.sheep state={:celebrating} size="lg" />
        </div>

        <h2 class="text-2xl font-bold text-[#1C1C1E] mb-2">Review Complete!</h2>
        <p class="text-[#8E8E93] mb-6">Great job staying on top of your reviews.</p>

        <%!-- Stats --%>
        <div class="grid grid-cols-2 gap-4 mb-6">
          <div class="bg-[#F5F5F7] rounded-xl p-4">
            <p class="text-3xl font-bold text-[#4CD964]">{@cards_reviewed}</p>
            <p class="text-xs text-[#8E8E93] mt-1">Cards Reviewed</p>
          </div>
          <div class="bg-[#F5F5F7] rounded-xl p-4">
            <p class="text-3xl font-bold text-[#4CD964]">+{@xp_earned}</p>
            <p class="text-xs text-[#8E8E93] mt-1">XP Earned</p>
          </div>
        </div>

        <%!-- Next review hint --%>
        <div
          :if={assigns[:remaining_due] && @remaining_due > 0}
          class="bg-amber-50 rounded-xl p-4 mb-6"
        >
          <p class="text-sm text-amber-700">
            <.icon name="hero-clock" class="w-4 h-4 inline -mt-0.5" />
            {@remaining_due} more cards are due — start another batch anytime!
          </p>
        </div>

        <div
          :if={!assigns[:remaining_due] || @remaining_due == 0}
          class="bg-[#E8F8EB] rounded-xl p-4 mb-6"
        >
          <p class="text-sm text-[#4CD964]">
            <.icon name="hero-check-circle" class="w-4 h-4 inline -mt-0.5" />
            All caught up! Your next cards will be due soon.
          </p>
        </div>

        <.link
          navigate={~p"/dashboard"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors inline-block"
        >
          Back to Dashboard
        </.link>
      </div>
    </div>
    """
  end
end
