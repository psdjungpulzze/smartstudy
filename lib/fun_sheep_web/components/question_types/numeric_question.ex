defmodule FunSheepWeb.Components.NumericQuestion do
  @moduledoc """
  Renders a numeric question where the student enters a number.

  The input uses `type="number"` for a numeric keyboard on mobile devices.
  An optional unit label (from `question.options["unit"]`) is shown inline.
  Client-side validation prevents submission of non-numeric values.
  """

  use Phoenix.Component

  @doc """
  Renders a numeric question.

  ## Attributes

    * `question` - The question map/struct. Must have `:content` and `:options` fields.
      `options["unit"]` (optional) is a string label shown after the input (e.g. `"kg"`).
      `options["placeholder"]` (optional) overrides the default placeholder text.
    * `answer_given` - The student's current numeric input as a string.
      Defaults to `""`.
    * `submitted` - Whether the form has been submitted. Defaults to `false`.
    * `correct_answer` - The correct answer string, shown after submission.
      Defaults to `nil`.
    * `on_submit` - The `phx-submit` event name. Defaults to `"submit_answer"`.
    * `id` - Unique id for this component instance.
  """

  attr :question, :map, required: true
  attr :answer_given, :string, default: ""
  attr :submitted, :boolean, default: false
  attr :correct_answer, :string, default: nil
  attr :on_submit, :string, default: "submit_answer"
  attr :id, :string, default: nil

  def numeric_question(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn ->
        "numeric-#{System.unique_integer([:positive])}"
      end)
      |> assign(:unit, get_opt(assigns.question, "unit"))
      |> assign(:placeholder, get_opt(assigns.question, "placeholder") || "Enter a number")
      |> assign(:result_state, result_state(assigns))

    ~H"""
    <div id={@id} class="w-full">
      <p class="text-base font-semibold text-gray-900 dark:text-white mb-4">
        {@question.content}
      </p>

      <form id={"#{@id}-form"} phx-submit={@on_submit}>
        <div class="flex items-center gap-2 mb-6">
          <input
            type="number"
            name="answer"
            value={@answer_given}
            disabled={@submitted}
            placeholder={@placeholder}
            required
            class={[
              "flex-1 px-4 py-3 rounded-full border text-base outline-none transition-colors",
              "bg-white dark:bg-gray-800",
              input_classes(@result_state)
            ]}
          />
          <span
            :if={@unit}
            class="text-sm font-medium text-gray-500 dark:text-gray-400 whitespace-nowrap"
          >
            {@unit}
          </span>
        </div>

        <div :if={@submitted and @correct_answer} class="mb-4 text-sm">
          <%= if @result_state == :correct do %>
            <p class="text-[#4CD964] font-medium">Correct!</p>
          <% else %>
            <p class="text-[#FF3B30] font-medium">
              Incorrect. The correct answer is {@correct_answer}{if @unit, do: " #{@unit}", else: ""}.
            </p>
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

  defp get_opt(%{options: opts}, key) when is_map(opts), do: Map.get(opts, key)
  defp get_opt(_, _), do: nil

  defp result_state(%{submitted: false}), do: :idle

  defp result_state(%{submitted: true, answer_given: given, correct_answer: correct})
       when is_binary(given) and is_binary(correct) do
    case {Float.parse(given), Float.parse(correct)} do
      {{g, ""}, {c, ""}} when g == c -> :correct
      _ -> :incorrect
    end
  end

  defp result_state(_), do: :idle

  defp input_classes(:idle),
    do: "border-gray-300 dark:border-gray-600 focus:border-[#4CD964]"

  defp input_classes(:correct),
    do: "border-[#4CD964] bg-[#E8F8EB] dark:bg-green-900/20"

  defp input_classes(:incorrect),
    do: "border-[#FF3B30] bg-red-50 dark:bg-red-900/20"
end
