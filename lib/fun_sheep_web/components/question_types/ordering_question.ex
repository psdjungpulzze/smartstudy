defmodule FunSheepWeb.Components.OrderingQuestion do
  @moduledoc """
  Renders an ordering question where students arrange items in the correct sequence.

  Items are displayed in shuffled order (from `question.options["items"]`). The
  student uses ↑ / ↓ arrow buttons to reorder them.

  On submit, the current order is collected as a comma-separated string matching
  the `OrderingGrader` input format (e.g. `"B,A,C"`).

  State management (the live order) is handled by the parent LiveView via events.
  The component emits `phx-click` events on the arrow buttons with the item key
  and direction, so the parent can update the `answer_given` assign and re-render.
  """

  use Phoenix.Component

  @doc """
  Renders an ordering question.

  ## Attributes

    * `question` - The question map/struct. Must have `:content` and `:options` fields.
      `options["items"]` is a map of `%{"key" => "label"}` for items to order.
    * `answer_given` - Comma-separated current ordering of keys, e.g. `"B,A,C"`.
      If empty or `nil`, the items are shown in their original shuffled order.
    * `submitted` - Whether the form has been submitted. Defaults to `false`.
    * `correct_answer` - Comma-separated correct order, shown after submission.
      Defaults to `nil`.
    * `on_submit` - The `phx-submit` event name. Defaults to `"submit_answer"`.
    * `on_move` - The `phx-click` event name for reorder arrows. Defaults to
      `"reorder_item"`. The event receives `%{"key" => key, "dir" => "up"|"down"}`.
    * `id` - Unique id for this component instance.
  """

  attr :question, :map, required: true
  attr :answer_given, :string, default: nil
  attr :submitted, :boolean, default: false
  attr :correct_answer, :string, default: nil
  attr :on_submit, :string, default: "submit_answer"
  attr :on_move, :string, default: "reorder_item"
  attr :id, :string, default: nil

  def ordering_question(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn ->
        "ordering-#{System.unique_integer([:positive])}"
      end)
      |> assign(:ordered_items, build_ordered_items(assigns.question, assigns.answer_given))
      |> assign(:correct_seq, parse_seq(assigns[:correct_answer]))

    ~H"""
    <div id={@id} class="w-full">
      <p class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">
        Arrange the items in the correct order
      </p>

      <p class="text-base font-semibold text-gray-900 dark:text-white mb-4">
        {@question.content}
      </p>

      <form id={"#{@id}-form"} phx-submit={@on_submit}>
        <%!-- Hidden field carries the current order as comma-separated keys --%>
        <input
          type="hidden"
          name="ordering"
          value={@ordered_items |> Enum.map(&elem(&1, 0)) |> Enum.join(",")}
        />

        <div class="space-y-2 mb-6">
          <%= for {{key, label}, idx} <- Enum.with_index(@ordered_items) do %>
            <% is_last = idx == length(@ordered_items) - 1 %>
            <% correct_idx = Enum.find_index(@correct_seq, &(&1 == key)) %>
            <% placed_correctly = @submitted and correct_idx == idx %>
            <div class={[
              "flex items-center gap-3 px-4 py-3 rounded-2xl border",
              "transition-colors",
              item_classes(@submitted, placed_correctly)
            ]}>
              <span class="w-7 h-7 rounded-full bg-gray-100 dark:bg-gray-700 text-xs font-semibold flex items-center justify-center text-gray-600 dark:text-gray-300 shrink-0">
                {idx + 1}
              </span>

              <span class="flex-1 text-sm text-gray-900 dark:text-white">
                {label}
              </span>

              <div :if={not @submitted} class="flex flex-col gap-0.5 shrink-0">
                <button
                  :if={idx > 0}
                  type="button"
                  phx-click={@on_move}
                  phx-value-key={key}
                  phx-value-dir="up"
                  aria-label="Move up"
                  class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="m4.5 15.75 7.5-7.5 7.5 7.5"
                    />
                  </svg>
                </button>
                <button
                  :if={not is_last}
                  type="button"
                  phx-click={@on_move}
                  phx-value-key={key}
                  phx-value-dir="down"
                  aria-label="Move down"
                  class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="m19.5 8.25-7.5 7.5-7.5-7.5"
                    />
                  </svg>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <button
          :if={not @submitted}
          type="submit"
          class="w-full bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium py-3 rounded-full shadow-md transition-colors"
        >
          Submit Answer
        </button>
      </form>
    </div>
    """
  end

  # Build ordered list of {key, label} tuples.
  # If answer_given is set, honour that order; otherwise use shuffled item order.
  defp build_ordered_items(question, answer_given) do
    items_map = get_items_map(question)

    case parse_seq(answer_given) do
      [] ->
        items_map |> Enum.to_list() |> Enum.shuffle()

      keys ->
        keys
        |> Enum.filter(&Map.has_key?(items_map, &1))
        |> Enum.map(&{&1, Map.get(items_map, &1)})
    end
  end

  defp get_items_map(%{options: %{"items" => items}}) when is_map(items), do: items
  defp get_items_map(_), do: %{}

  defp parse_seq(nil), do: []
  defp parse_seq(""), do: []

  defp parse_seq(csv) when is_binary(csv),
    do: csv |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp item_classes(false, _correct),
    do: "border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800"

  defp item_classes(true, true), do: "border-[#4CD964] bg-[#E8F8EB] dark:bg-green-900/20"
  defp item_classes(true, false), do: "border-[#FF3B30] bg-red-50 dark:bg-red-900/20"
end
