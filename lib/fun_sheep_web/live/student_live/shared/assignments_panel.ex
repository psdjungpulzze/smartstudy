defmodule FunSheepWeb.StudentLive.Shared.AssignmentsPanel do
  @moduledoc """
  Shared practice-assignments panel (spec §7.2).

  Renders the parent's open assignments, with real attempted/correct
  numbers once the student has started. The list is capped at the
  business rule from `FunSheep.Accountability` — the panel also
  visualises how many open slots remain so the parent doesn't try to
  flood.
  """

  use FunSheepWeb, :html

  attr :assignments, :list, required: true
  attr :open_slots, :integer, required: true, doc: "Number of slots still available"
  attr :class, :string, default: nil

  def panel(assigns) do
    ~H"""
    <section class={["bg-white rounded-2xl border border-gray-100 p-4 sm:p-5", @class]}>
      <div class="flex items-start justify-between gap-3 mb-3">
        <div>
          <h3 class="text-sm font-extrabold text-gray-900">
            {gettext("Parent-assigned practice")}
          </h3>
          <p class="text-xs text-gray-500">
            {gettext("Nudges, not a flood. %{n} open slots remaining.", n: @open_slots)}
          </p>
        </div>
      </div>

      <div :if={@assignments == []} class="py-6 text-center">
        <p class="text-sm text-gray-500">
          {gettext("No open assignments. Tap a weak topic to assign practice.")}
        </p>
      </div>

      <ul :if={@assignments != []} class="space-y-2">
        <.assignment_row :for={assignment <- @assignments} assignment={assignment} />
      </ul>
    </section>
    """
  end

  attr :assignment, :any, required: true

  defp assignment_row(assigns) do
    ~H"""
    <li class="rounded-xl border border-gray-100 p-3 list-none">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-bold text-gray-900 truncate">
            {section_name(@assignment)}
          </p>
          <p class="text-xs text-gray-500 mt-0.5">
            {@assignment.question_count} {gettext("questions")}
            <span :if={@assignment.due_date}>
              · {gettext("due")} {Date.to_string(@assignment.due_date)}
            </span>
          </p>
          <p :if={@assignment.questions_attempted > 0} class="text-xs text-gray-500 mt-0.5">
            {@assignment.questions_correct}/{@assignment.questions_attempted} {gettext("correct")}
          </p>
        </div>
        <span class={[
          "text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0",
          status_classes(@assignment.status)
        ]}>
          {status_label(@assignment.status)}
        </span>
      </div>
    </li>
    """
  end

  defp section_name(%{section: %{name: n}}) when is_binary(n), do: n
  defp section_name(%{chapter: %{name: n}}) when is_binary(n), do: n
  defp section_name(_), do: gettext("Practice set")

  defp status_classes(:pending), do: "bg-sky-50 text-sky-700"
  defp status_classes(:in_progress), do: "bg-amber-50 text-amber-700"
  defp status_classes(:completed), do: "bg-[#E8F8EB] text-[#256029]"
  defp status_classes(:expired), do: "bg-gray-100 text-gray-500"

  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:in_progress), do: gettext("In progress")
  defp status_label(:completed), do: gettext("Done")
  defp status_label(:expired), do: gettext("Expired")
end
