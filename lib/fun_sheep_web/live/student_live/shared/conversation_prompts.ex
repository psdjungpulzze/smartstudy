defmodule FunSheepWeb.StudentLive.Shared.ConversationPrompts do
  @moduledoc """
  Renders parent-only conversation-prompt cards (spec §7.3).

  The prompt list is computed by
  `FunSheep.Accountability.conversation_prompts_for_parent/2` and
  contains only real, goal-driven cards. This component never surfaces
  a prompt to the student — the opener is a script for the parent.
  """

  use FunSheepWeb, :html

  attr :prompts, :list, required: true
  attr :class, :string, default: nil

  def card(assigns) do
    assigns = assign(assigns, :empty?, assigns.prompts == [])

    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="mb-3">
        <h3 class="text-sm font-extrabold text-gray-900">
          {gettext("Conversation starter")}
        </h3>
        <p class="text-xs text-gray-500">
          {gettext("A script for you — not sent to your student.")}
        </p>
      </div>

      <div :if={@empty?} class="py-4">
        <p class="text-sm text-gray-500">
          {gettext("Nothing to flag this week. Consider celebrating effort.")}
        </p>
      </div>

      <ul :if={!@empty?} class="space-y-3">
        <.prompt :for={p <- @prompts} prompt={p} />
      </ul>
    </section>
    """
  end

  attr :prompt, :map, required: true

  defp prompt(assigns) do
    ~H"""
    <li class="rounded-xl border border-gray-100 bg-gray-50 p-3 list-none">
      <p class="text-xs text-gray-500">
        {gettext("Your student")} {@prompt.summary}.
      </p>
      <p class="text-sm font-bold text-gray-900 mt-2 italic">
        &ldquo;{@prompt.opener}&rdquo;
      </p>
      <p class="text-[11px] text-gray-400 mt-1">{@prompt.rationale}</p>
    </li>
    """
  end
end
