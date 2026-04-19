defmodule FunSheepWeb.ProofCardLive do
  use FunSheepWeb, :live_view

  import Ecto.Query
  alias FunSheep.Repo
  alias FunSheep.Engagement.ProofCard

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    proof_card =
      from(pc in ProofCard,
        where: pc.share_token == ^token,
        preload: [:user_role, :course]
      )
      |> Repo.one()

    socket =
      assign(socket,
        page_title: proof_card_title(proof_card),
        proof_card: proof_card
      )

    {:ok, socket, layout: {FunSheepWeb.Layouts, :root}}
  end

  defp proof_card_title(nil), do: "Not Found"

  defp proof_card_title(card) do
    case card.card_type do
      "readiness_jump" -> "Readiness Achievement"
      "streak_milestone" -> "Streak Milestone"
      "weekly_rank" -> "Weekly Ranking"
      "session_receipt" -> "Study Session"
      _ -> "Achievement"
    end
  end

  defp first_name(nil), do: "Student"

  defp first_name(user_role) do
    name = user_role.display_name || ""

    name
    |> String.split(" ")
    |> List.first()
    |> case do
      nil -> "Student"
      "" -> "Student"
      first -> first
    end
  end

  defp render_card_content(assigns) do
    case assigns.card.card_type do
      "readiness_jump" -> render_readiness_jump(assigns)
      "streak_milestone" -> render_streak_milestone(assigns)
      "weekly_rank" -> render_weekly_rank(assigns)
      "session_receipt" -> render_session_receipt(assigns)
      _ -> render_generic(assigns)
    end
  end

  defp render_readiness_jump(assigns) do
    metrics = assigns.card.metrics || %{}
    from_val = metrics["from"] || 0
    to_val = metrics["to"] || 0
    subject = if assigns.card.course, do: assigns.card.course.name, else: "Study"

    assigns =
      assigns
      |> assign(:from_val, from_val)
      |> assign(:to_val, to_val)
      |> assign(:subject, subject)

    ~H"""
    <div class="text-center">
      <p class="text-white/70 text-sm font-medium uppercase tracking-wider mb-2">
        {@subject} Readiness
      </p>
      <div class="flex items-center justify-center gap-3 mb-2">
        <span class="text-4xl font-bold text-white/60">{@from_val}%</span>
        <svg
          class="w-8 h-8 text-white"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M13 7l5 5m0 0l-5 5m5-5H6" />
        </svg>
        <span class="text-5xl font-extrabold text-white">{@to_val}%</span>
      </div>
      <p class="text-white/80 text-lg font-medium">+{@to_val - @from_val}% improvement!</p>
    </div>
    """
  end

  defp render_streak_milestone(assigns) do
    metrics = assigns.card.metrics || %{}
    days = metrics["days"] || 0
    assigns = assign(assigns, :days, days)

    ~H"""
    <div class="text-center">
      <p class="text-6xl mb-2">🔥</p>
      <p class="text-4xl font-extrabold text-white mb-1">{@days}-Day</p>
      <p class="text-2xl font-bold text-white">Study Streak!</p>
      <p class="text-white/70 text-sm mt-2">Consistency is the key to mastery</p>
    </div>
    """
  end

  defp render_weekly_rank(assigns) do
    metrics = assigns.card.metrics || %{}
    rank = metrics["rank"] || 0

    medal =
      case rank do
        1 -> "🥇"
        2 -> "🥈"
        3 -> "🥉"
        _ -> "🏅"
      end

    assigns =
      assigns
      |> assign(:rank, rank)
      |> assign(:medal, medal)

    ~H"""
    <div class="text-center">
      <p class="text-6xl mb-2">{@medal}</p>
      <p class="text-4xl font-extrabold text-white mb-1">#{@rank}</p>
      <p class="text-xl font-bold text-white">in the Flock This Week</p>
    </div>
    """
  end

  defp render_session_receipt(assigns) do
    metrics = assigns.card.metrics || %{}
    questions = metrics["questions"] || 0
    accuracy = metrics["accuracy"] || 0

    assigns =
      assigns
      |> assign(:questions, questions)
      |> assign(:accuracy, accuracy)

    ~H"""
    <div class="text-center">
      <p class="text-5xl mb-3">📚</p>
      <p class="text-2xl font-bold text-white mb-1">
        Studied {@questions} questions
      </p>
      <p class="text-4xl font-extrabold text-white">{@accuracy}% accuracy</p>
    </div>
    """
  end

  defp render_generic(assigns) do
    ~H"""
    <div class="text-center">
      <p class="text-5xl mb-3">🐑</p>
      <p class="text-2xl font-bold text-white">{@card.title}</p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] flex items-center justify-center p-4">
      <%!-- Not found state --%>
      <div
        :if={@proof_card == nil}
        class="max-w-sm w-full bg-white rounded-2xl shadow-md p-8 text-center"
      >
        <p class="text-5xl mb-4">🐑</p>
        <h1 class="text-xl font-bold text-[#1C1C1E] mb-2">Card Not Found</h1>
        <p class="text-[#8E8E93]">
          This proof card doesn't exist or may have been removed.
        </p>
      </div>

      <%!-- Proof card --%>
      <div :if={@proof_card} class="max-w-sm w-full">
        <div class="rounded-2xl shadow-xl overflow-hidden">
          <%!-- Card body with green gradient --%>
          <div class="bg-gradient-to-br from-[#4CD964] to-[#2AA845] p-8 pb-6">
            <%!-- Logo / Branding --%>
            <div class="flex items-center justify-center gap-2 mb-6">
              <span class="text-2xl">🐑</span>
              <span class="text-white font-extrabold text-xl tracking-tight">FunSheep</span>
            </div>

            <%!-- Student name --%>
            <p class="text-white/80 text-center text-sm font-medium mb-6">
              {first_name(@proof_card.user_role)}'s Achievement
            </p>

            <%!-- Card content by type --%>
            <.render_card_content card={@proof_card} />

            <%!-- Percentile badge --%>
            <div
              :if={@proof_card.metrics["percentile"]}
              class="mt-6 mx-auto w-fit bg-white/20 backdrop-blur-sm rounded-full px-4 py-1.5"
            >
              <p class="text-white text-sm font-medium">
                Top {@proof_card.metrics["percentile"]}% of students
              </p>
            </div>
          </div>

          <%!-- CTA footer --%>
          <div class="bg-white px-8 py-5 text-center">
            <p class="text-[#8E8E93] text-xs mb-2">Study smarter with AI-powered learning</p>
            <p class="text-[#4CD964] font-bold text-base">Try FunSheep Free</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
