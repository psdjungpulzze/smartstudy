defmodule FunSheep.Scraper.Extractors.Albert do
  @moduledoc """
  Albert.io extractor.

  Albert.io renders server-side HTML for their practice questions with a
  predictable card structure. Questions, answer options, and explanations
  are in well-named CSS classes.

  Selectors (verified against 2024 Albert.io HTML snapshots):
    - `.question__text` or `.question-stem`          — question stem
    - `.choice__text` or `.answer-choice__text`      — each answer option
    - `.choice--correct` or `.answer-choice--correct` — correct option
    - `.explanation__text`                            — explanation

  Falls back to `Generic` when selectors yield nothing.
  """

  require Logger

  alias FunSheep.Scraper.Extractors.Generic

  @stem_selectors ~w(
    .question__text
    .question-stem
    .question-content
    [data-testid=question-stem]
  )

  @choice_selectors ~w(
    .choice__text
    .answer-choice__text
    .choice-option__text
    [data-testid=answer-choice]
  )

  @correct_class_patterns ~w(choice--correct answer-choice--correct correct-answer)
  @explanation_selectors ~w(.explanation__text .explanation-content .solution-text)

  @doc false
  def extract(html, url, opts) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        questions = parse_albert_questions(document, url, opts)

        if questions == [] do
          Logger.debug("[AlbertExtractor] No question cards, falling back for #{url}")
          Generic.extract(html, url, opts)
        else
          {:ok, questions}
        end

      {:error, _} ->
        Generic.extract(html, url, opts)
    end
  rescue
    _ -> Generic.extract(html, url, opts)
  end

  defp parse_albert_questions(document, url, opts) do
    # Albert can render multiple questions in a grid or single question per page
    containers = Floki.find(document, ".question-card, .question-item, .practice-item, .question")

    if containers != [] do
      Enum.flat_map(containers, &parse_question_node(&1, url, opts))
    else
      parse_question_node(document, url, opts)
    end
  end

  defp parse_question_node(node, url, opts) do
    stem = find_first_text(node, @stem_selectors)

    if is_nil(stem) or String.length(String.trim(stem)) < 20 do
      []
    else
      choices = find_choices(node)
      correct = find_correct_label(node, choices)
      explanation = find_first_text(node, @explanation_selectors)
      ref = opts[:source_ref] || %{}

      [
        %{
          content: String.trim(stem),
          answer: correct,
          question_type: if(map_size(choices) >= 2, do: :multiple_choice, else: :short_answer),
          options: if(map_size(choices) >= 2, do: choices, else: nil),
          difficulty: :medium,
          explanation: explanation,
          source_url: url,
          source_type: :web_scraped,
          is_generated: false,
          source_page: (opts[:source_ref] || %{})[:source_page],
          metadata: %{"source" => "web_scrape", "extractor" => "albert"},
          grounding_refs: %{"refs" => opts[:grounding_refs] || []}
        }
      ]
    end
  end

  defp find_first_text(node, selectors) do
    Enum.find_value(selectors, fn selector ->
      case Floki.find(node, selector) do
        [el | _] ->
          text = Floki.text(el) |> String.trim()
          if text != "", do: text, else: nil

        [] ->
          nil
      end
    end)
  end

  defp find_choices(node) do
    letters = ~w(A B C D E)

    @choice_selectors
    |> Enum.find_value(fn selector ->
      items = Floki.find(node, selector)
      if items != [], do: items, else: nil
    end)
    |> case do
      nil ->
        %{}

      items ->
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          label = Enum.at(letters, idx, "#{idx + 1}")
          text = Floki.text(item) |> String.trim()
          {label, text}
        end)
        |> Enum.reject(fn {_, text} -> text == "" end)
        |> Map.new()
    end
  end

  defp find_correct_label(_node, choices) when map_size(choices) == 0, do: ""

  defp find_correct_label(node, choices) do
    # Try to find which answer choice element has the correct CSS class
    @correct_class_patterns
    |> Enum.find_value(fn cls ->
      case Floki.find(node, ".#{cls}") do
        [correct_el | _] ->
          text = Floki.text(correct_el) |> String.trim()

          # Match the correct element's text against our choices map to get the letter
          Enum.find_value(choices, fn {label, choice_text} ->
            if String.starts_with?(choice_text, text) or String.starts_with?(text, choice_text) do
              label
            end
          end)

        [] ->
          nil
      end
    end) || ""
  end
end
