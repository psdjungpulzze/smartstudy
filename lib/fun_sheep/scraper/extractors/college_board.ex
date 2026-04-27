defmodule FunSheep.Scraper.Extractors.CollegeBoard do
  @moduledoc """
  College Board extractor.

  College Board HTML pages (SAT practice, AP practice, etc.) render
  server-side with accessible markup. Questions are typically inside
  `.question-body`, `.item-body`, or similar containers.

  For PDF URLs: College Board PDFs (official practice tests, AP FRQ PDFs)
  are routed to the binary-document pipeline via the scraper worker
  *before* reaching this extractor — this module only handles HTML pages.

  Falls back to `Generic` when selectors yield nothing, which is common
  for College Board's more interactive JS-heavy pages.
  """

  require Logger

  alias FunSheep.Scraper.Extractors.Generic

  @stem_selectors ~w(
    .question-body
    .item-body
    .passage-question
    [data-automation=question-stem]
    .cbQuestionBody
    .test-question
  )

  @choice_selectors ~w(
    .answer-option
    .cbAnswerOption
    .answer-choice
    [data-automation=answer-option]
    li.choice
  )

  @doc false
  def extract(html, url, opts) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        questions = parse_cb_questions(document, url, opts)

        if questions == [] do
          Logger.debug("[CBExtractor] No CB question selectors matched, falling back for #{url}")
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

  defp parse_cb_questions(document, url, opts) do
    containers =
      Floki.find(document, ".question-item, .item-container, .test-question-container")

    if containers != [] do
      Enum.flat_map(containers, &parse_cb_question(&1, url, opts))
    else
      parse_cb_question(document, url, opts)
    end
  end

  defp parse_cb_question(node, url, opts) do
    stem = find_first_text(node, @stem_selectors)

    if is_nil(stem) or String.length(String.trim(stem)) < 20 do
      []
    else
      choices = find_choices(node)
      ref = opts[:source_ref] || %{}

      [
        %{
          content: String.trim(stem),
          answer: "",
          question_type: if(map_size(choices) >= 2, do: :multiple_choice, else: :short_answer),
          options: if(map_size(choices) >= 2, do: choices, else: nil),
          difficulty: :medium,
          explanation: nil,
          source_url: url,
          source_type: :web_scraped,
          is_generated: false,
          source_page: ref[:source_page],
          metadata: %{"source" => "web_scrape", "extractor" => "college_board"},
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
end
