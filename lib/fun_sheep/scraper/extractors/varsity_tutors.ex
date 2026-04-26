defmodule FunSheep.Scraper.Extractors.VarsityTutors do
  @moduledoc """
  VarsityTutors extractor.

  VarsityTutors renders server-side HTML with a consistent question card
  structure. Questions and answer choices are in predictable CSS classes.

  Selectors (verified against the 2024 HTML snapshot):
    - `.question-text` or `.vtQuestionText`     — question stem
    - `.answer-choice` or `.vtAnswerChoice`      — each answer option
    - `.correct-answer` or `.vtCorrectAnswer`    — correct option indicator
    - `.explanation` or `.vtExplanation`         — explanation text

  Falls back to `Generic` when none of these selectors produce results
  (e.g. a subject listing page rather than a question page).
  """

  require Logger

  alias FunSheep.Scraper.Extractors.Generic

  # Try these selectors for the question stem in order
  @stem_selectors ~w(.question-text .vtQuestionText .question-body .question h2.question)

  # Try these for each answer option
  @choice_selectors ~w(.answer-choice .vtAnswerChoice .choice .answer-option li.answer)

  # Indicates the correct answer
  @correct_selectors ~w(.correct-answer .vtCorrectAnswer .correct .answer--correct)

  # Explanation text
  @explanation_selectors ~w(.explanation .vtExplanation .solution .answer-explanation)

  @doc false
  def extract(html, url, opts) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        questions = extract_question_cards(document, url, opts)

        if questions == [] do
          Logger.debug("[VTExtractor] No question cards found, falling back for #{url}")
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

  defp extract_question_cards(document, url, opts) do
    # VarsityTutors may show multiple questions on a practice page.
    # Try to find individual question containers first.
    containers = find_question_containers(document)

    if containers != [] do
      Enum.flat_map(containers, &parse_container(&1, url, opts))
    else
      # Single-question page — treat the whole document as one question
      case parse_container(document, url, opts) do
        [] -> []
        questions -> questions
      end
    end
  end

  defp find_question_containers(document) do
    Floki.find(document, ".question-container, .vtQuestion, .practice-question, .question-block")
  end

  defp parse_container(node, url, opts) do
    stem = find_first_text(node, @stem_selectors)

    if is_nil(stem) or String.length(String.trim(stem)) < 20 do
      []
    else
      choices = find_choices(node)
      correct = find_correct(node, choices)
      explanation = find_first_text(node, @explanation_selectors)
      ref = opts[:source_ref] || %{}

      q = %{
        content: String.trim(stem),
        answer: correct,
        question_type: if(map_size(choices) >= 2, do: :multiple_choice, else: :short_answer),
        options: if(map_size(choices) >= 2, do: choices, else: nil),
        difficulty: :medium,
        explanation: explanation,
        source_url: url,
        source_type: :web_scraped,
        is_generated: false,
        source_page: ref[:source_page],
        metadata: %{"source" => "web_scrape", "extractor" => "varsity_tutors"},
        grounding_refs: %{"refs" => opts[:grounding_refs] || []}
      }

      [q]
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

  defp find_correct(node, choices) when map_size(choices) == 0, do: ""

  defp find_correct(node, _choices) do
    @correct_selectors
    |> Enum.find_value(fn selector ->
      case Floki.find(node, selector) do
        [el | _] ->
          text = Floki.text(el) |> String.trim()
          if text != "", do: text, else: nil

        [] ->
          nil
      end
    end) || ""
  end
end
