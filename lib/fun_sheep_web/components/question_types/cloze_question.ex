defmodule FunSheepWeb.Components.ClozeQuestion do
  @moduledoc """
  Renders a cloze (fill-in-the-blank) question.

  The passage text in `question.content` may contain `__N__` placeholders
  (e.g. `__1__`, `__2__`) which are replaced with interactive inputs.

  If `question.options["blanks"][n]["word_bank"]` is a non-empty list the blank
  renders as a `<select>` dropdown; otherwise a plain text `<input>` is used.

  On submit, all blank values are collected and Jason-encoded into a map
  `%{"1" => "value1", "2" => "value2"}` to match the `ClozeGrader` input format.
  """

  use Phoenix.Component

  @doc """
  Renders a cloze fill-in-the-blank question.

  ## Attributes

    * `question` - The question map/struct.
    * `answer_given` - JSON-encoded map of blank answers, e.g. `~s({"1":"word"})`.
      Defaults to `"{}"`.
    * `submitted` - Whether the form has been submitted. Defaults to `false`.
    * `correct_answer` - JSON-encoded correct answer map, shown after submission.
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

  def cloze_question(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn ->
        "cloze-#{System.unique_integer([:positive])}"
      end)
      |> assign(:given_map, decode_map(assigns.answer_given))
      |> assign(:correct_map, decode_map(assigns[:correct_answer]))
      |> assign(:parts, split_passage(assigns.question.content))
      |> assign(:blanks_config, get_blanks_config(assigns.question))

    ~H"""
    <div id={@id} class="w-full">
      <p class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-4">
        Fill in the blanks
      </p>

      <form id={"#{@id}-form"} phx-submit={@on_submit}>
        <div class="text-base text-gray-900 dark:text-white leading-loose mb-6">
          <%= for part <- @parts do %>
            <%= case part do %>
              <% {:text, text} -> %>
                <span>{text}</span>
              <% {:blank, n} -> %>
                <% key = Integer.to_string(n) %>
                <% word_bank = get_in(@blanks_config, [key, "word_bank"]) || [] %>
                <% current_val = Map.get(@given_map, key, "") %>
                <% correct_val = Map.get(@correct_map, key, "") %>
                <%= if word_bank != [] do %>
                  <select
                    name={"blanks[#{key}]"}
                    disabled={@submitted}
                    class={[
                      "inline-block mx-1 px-3 py-1 rounded-lg border text-sm",
                      "bg-white dark:bg-gray-800 transition-colors",
                      blank_classes(@submitted, current_val, correct_val)
                    ]}
                  >
                    <option value="">— choose —</option>
                    <%= for word <- word_bank do %>
                      <option value={word} selected={current_val == word}>{word}</option>
                    <% end %>
                  </select>
                <% else %>
                  <input
                    type="text"
                    name={"blanks[#{key}]"}
                    value={current_val}
                    disabled={@submitted}
                    placeholder={"blank #{key}"}
                    class={[
                      "inline-block mx-1 px-3 py-1 w-32 rounded-lg border text-sm",
                      "bg-white dark:bg-gray-800 outline-none transition-colors",
                      blank_classes(@submitted, current_val, correct_val)
                    ]}
                  />
                <% end %>
            <% end %>
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

  # Splits the passage content into alternating text / blank tokens.
  # "__1__" becomes `{:blank, 1}`, surrounding text becomes `{:text, "..."}`.
  defp split_passage(nil), do: []

  defp split_passage(content) do
    content
    |> String.split(~r/__(\d+)__/, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/^__(\d+)__$/, part) do
        [_, n_str] -> {:blank, String.to_integer(n_str)}
        _ -> {:text, part}
      end
    end)
    |> Enum.reject(fn
      {:text, ""} -> true
      _ -> false
    end)
  end

  defp decode_map(nil), do: %{}
  defp decode_map(json) when is_binary(json), do: Jason.decode!(json)
  defp decode_map(_), do: %{}

  defp get_blanks_config(%{options: %{"blanks" => blanks}}) when is_map(blanks), do: blanks
  defp get_blanks_config(_), do: %{}

  defp blank_classes(false, _current, _correct),
    do: "border-gray-300 dark:border-gray-600 focus:border-[#4CD964]"

  defp blank_classes(true, current, correct) do
    cond do
      String.downcase(current) == String.downcase(correct) ->
        "border-[#4CD964] bg-[#E8F8EB] dark:bg-green-900/20"

      current == "" ->
        "border-gray-300 dark:border-gray-600"

      true ->
        "border-[#FF3B30] bg-red-50 dark:bg-red-900/20"
    end
  end
end
