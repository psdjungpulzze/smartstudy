defmodule FunSheepWeb.Components.MultiSelectQuestion do
  @moduledoc """
  Renders a multi-select question where students choose one or more correct options.

  Accepts any number of checkboxes. On submit, all checked option keys are
  sorted and joined with commas to match the `MultiSelectGrader` input format.
  """

  use Phoenix.Component

  @doc """
  Renders a multi-select (select-all-that-apply) question.

  ## Attributes

    * `question` - The question map/struct. Must have `:content` and `:options` fields.
      `options["choices"]` should be a map of `%{"key" => "label"}` pairs.
    * `answer_given` - List of selected keys (e.g. `["a", "c"]`). Defaults to `[]`.
    * `submitted` - Whether the form has been submitted. Defaults to `false`.
    * `correct_answer` - Comma-separated correct keys to show after submission.
      Defaults to `nil` (not shown).
    * `on_submit` - The `phx-submit` event name. Defaults to `"submit_answer"`.
    * `id` - Unique id for this component instance.
  """

  attr :question, :map, required: true
  attr :answer_given, :list, default: []
  attr :submitted, :boolean, default: false
  attr :correct_answer, :string, default: nil
  attr :on_submit, :string, default: "submit_answer"
  attr :id, :string, default: nil

  def multi_select_question(assigns) do
    assigns =
      assign_new(assigns, :id, fn ->
        "multi-select-#{System.unique_integer([:positive])}"
      end)

    ~H"""
    <div id={@id} class="w-full">
      <p class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">
        Select all that apply
      </p>

      <p class="text-base font-semibold text-gray-900 dark:text-white mb-4">
        {@question.content}
      </p>

      <form id={"#{@id}-form"} phx-submit={@on_submit}>
        <div class="space-y-3 mb-6">
          <%= for {key, label} <- choices(@question) do %>
            <% checked = key in @answer_given %>
            <% correct_keys =
              if @correct_answer,
                do: String.split(@correct_answer, ",") |> Enum.map(&String.trim/1),
                else: [] %>
            <% is_correct_key = key in correct_keys %>
            <label class={[
              "flex items-center gap-3 px-4 py-3 rounded-2xl border cursor-pointer",
              "transition-colors select-none",
              choice_classes(@submitted, checked, is_correct_key)
            ]}>
              <input
                type="checkbox"
                name="answers[]"
                value={key}
                checked={checked}
                disabled={@submitted}
                class="w-5 h-5 rounded accent-[#4CD964]"
              />
              <span class="text-sm text-gray-800 dark:text-gray-200">{label}</span>
            </label>
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

  defp choices(%{options: %{"choices" => choices}}) when is_map(choices), do: choices
  defp choices(_), do: %{}

  defp choice_classes(_submitted = false, _checked, _correct) do
    [
      "border-gray-200 dark:border-gray-700",
      "bg-white dark:bg-gray-800",
      "hover:border-[#4CD964] hover:bg-[#E8F8EB] dark:hover:bg-gray-700"
    ]
  end

  defp choice_classes(_submitted = true, checked, is_correct_key) do
    cond do
      checked and is_correct_key ->
        "border-[#4CD964] bg-[#E8F8EB] dark:bg-green-900/20"

      checked and not is_correct_key ->
        "border-[#FF3B30] bg-red-50 dark:bg-red-900/20"

      not checked and is_correct_key ->
        "border-[#4CD964] bg-[#E8F8EB]/50 dark:bg-green-900/10"

      true ->
        "border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800"
    end
  end
end
