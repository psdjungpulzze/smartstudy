defmodule FunSheepWeb.Components.MatchingQuestion do
  @moduledoc """
  Renders a matching question where students pair items from two columns.

  The left column contains prompt items (keys); the right column choices are
  shuffled on render. Each left item has a dropdown to select the matching
  right item.

  On submit the selections are collected as a Jason-encoded map
  `%{"A" => "2", "B" => "3"}` matching the `MatchingGrader` input format.
  """

  use Phoenix.Component

  @doc """
  Renders a matching question.

  ## Attributes

    * `question` - The question map/struct. Must have `:content` and `:options` fields.
      `options["left"]` is a map of `%{"key" => "label"}` for the left column.
      `options["right"]` is a map of `%{"key" => "label"}` for the right column.
    * `answer_given` - JSON-encoded map of current selections, e.g. `~s({"A":"2"})`.
      Defaults to `"{}"`.
    * `submitted` - Whether the form has been submitted. Defaults to `false`.
    * `correct_answer` - JSON-encoded correct map, shown after submission.
      Defaults to `nil`.
    * `on_submit` - The `phx-submit` event name. Defaults to `"submit_answer"`.
    * `id` - Unique id for this component instance.
  """

  attr :question, :map, required: true
  attr :answer_given, :string, default: "{}"
  attr :submitted, :boolean, default: false
  attr :correct_answer, :string, default: nil
  attr :on_submit, :string, default: "submit_answer"
  attr :id, :string, default: nil

  def matching_question(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn ->
        "matching-#{System.unique_integer([:positive])}"
      end)
      |> assign(:given_map, decode_map(assigns.answer_given))
      |> assign(:correct_map, decode_map(assigns[:correct_answer]))
      |> assign(:left_items, get_left(assigns.question))
      |> assign(:right_items, get_right_shuffled(assigns.question))

    ~H"""
    <div id={@id} class="w-full">
      <p class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">
        Match each item on the left to the correct item on the right
      </p>

      <p class="text-base font-semibold text-gray-900 dark:text-white mb-4">
        {@question.content}
      </p>

      <form id={"#{@id}-form"} phx-submit={@on_submit}>
        <div class="space-y-3 mb-6">
          <%= for {left_key, left_label} <- @left_items do %>
            <% selected_val = Map.get(@given_map, left_key, "") %>
            <% correct_val = Map.get(@correct_map, left_key, "") %>
            <div class="flex items-center gap-3">
              <span class={[
                "flex-1 px-4 py-2.5 rounded-2xl border text-sm font-medium",
                "bg-white dark:bg-gray-800 text-gray-900 dark:text-white",
                "border-gray-200 dark:border-gray-700"
              ]}>
                {left_label}
              </span>

              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-5 h-5 text-gray-400 shrink-0"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3"
                />
              </svg>

              <select
                name={"pairs[#{left_key}]"}
                disabled={@submitted}
                class={[
                  "flex-1 px-4 py-2.5 rounded-xl border text-sm",
                  "bg-white dark:bg-gray-800 transition-colors",
                  select_classes(@submitted, selected_val, correct_val)
                ]}
              >
                <option value="">— select —</option>
                <%= for {right_key, right_label} <- @right_items do %>
                  <option value={right_key} selected={selected_val == right_key}>
                    {right_label}
                  </option>
                <% end %>
              </select>
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

  defp decode_map(nil), do: %{}
  defp decode_map(json) when is_binary(json), do: Jason.decode!(json)
  defp decode_map(_), do: %{}

  defp get_left(%{options: %{"left" => left}}) when is_map(left), do: Enum.sort(left)
  defp get_left(_), do: []

  defp get_right_shuffled(%{options: %{"right" => right}}) when is_map(right) do
    right |> Enum.to_list() |> Enum.shuffle()
  end

  defp get_right_shuffled(_), do: []

  defp select_classes(false, _selected, _correct),
    do: "border-gray-300 dark:border-gray-600 focus:border-[#4CD964]"

  defp select_classes(true, selected, correct) do
    cond do
      selected == correct -> "border-[#4CD964] bg-[#E8F8EB] dark:bg-green-900/20"
      selected == "" -> "border-gray-300 dark:border-gray-600"
      true -> "border-[#FF3B30] bg-red-50 dark:bg-red-900/20"
    end
  end
end
