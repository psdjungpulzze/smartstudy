defmodule FunSheep.Scraper.Extractors.KhanAcademy do
  @moduledoc """
  Khan Academy extractor.

  KA exercise pages embed all question data in a `<script id="__NEXT_DATA__">`
  JSON blob (Next.js Perseus format). Parsing that blob avoids an AI call and
  returns perfectly-structured question data.

  Extraction path:
    1. Look for `<script id="__NEXT_DATA__">` and parse its JSON.
    2. Walk `props.pageProps.dehydratedState` looking for Perseus items with
       "question" + "answers" shapes.
    3. If no Perseus data found (e.g. a category listing page), fall back
       to `Generic` so the AI path gets a chance.

  Returns `{:ok, [question_map()]}` — always, never raises.
  """

  require Logger

  alias FunSheep.Scraper.Extractors.Generic

  @doc false
  def extract(html, url, opts) when is_binary(html) do
    case extract_next_data(html) do
      {:ok, questions} when questions != [] ->
        tagged = Enum.map(questions, &tag_source(&1, url, opts))
        {:ok, tagged}

      _ ->
        # Not a Perseus exercise page (category listing, profile, etc.) —
        # fall back to generic AI extraction on the parsed text.
        Logger.debug("[KAExtractor] No Perseus data, falling back to Generic for #{url}")
        Generic.extract(html, url, opts)
    end
  end

  defp extract_next_data(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        case Floki.find(document, "script#__NEXT_DATA__") do
          [{_, _, children} | _] ->
            # Floki.text/1 skips <script> content in 0.38+; access children directly.
            raw = children |> Enum.filter(&is_binary/1) |> Enum.join()
            parse_perseus(raw)

          _ ->
            {:ok, []}
        end

      {:error, _} ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  defp parse_perseus(json_text) when is_binary(json_text) do
    case Jason.decode(json_text) do
      {:ok, data} ->
        questions =
          data
          |> find_perseus_items()
          |> Enum.flat_map(&item_to_question/1)

        {:ok, questions}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  # Recursively search for objects that look like Perseus exercise items.
  # Perseus items have a "question" key with a "content" string and an
  # "answers" list. They may be deeply nested inside dehydratedState.
  defp find_perseus_items(data) when is_map(data) do
    cond do
      perseus_item?(data) ->
        [data]

      true ->
        data
        |> Map.values()
        |> Enum.flat_map(&find_perseus_items/1)
    end
  end

  defp find_perseus_items(data) when is_list(data) do
    Enum.flat_map(data, &find_perseus_items/1)
  end

  defp find_perseus_items(_), do: []

  defp perseus_item?(%{"question" => %{"content" => content}, "answers" => answers})
       when is_binary(content) and is_list(answers),
       do: true

  defp perseus_item?(_), do: false

  defp item_to_question(%{"question" => %{"content" => stem}, "answers" => answers}) do
    stem_text = strip_perseus_markup(stem)

    if String.length(String.trim(stem_text)) < 20 do
      []
    else
      {opts, correct} = parse_answers(answers)

      [
        %{
          content: stem_text,
          answer: correct,
          question_type: if(map_size(opts) >= 2, do: :multiple_choice, else: :short_answer),
          options: if(map_size(opts) >= 2, do: opts, else: nil),
          difficulty: :medium,
          explanation: nil
        }
      ]
    end
  end

  defp item_to_question(_), do: []

  defp parse_answers(answers) when is_list(answers) do
    letters = ~w(A B C D E)

    {opts, correct} =
      answers
      |> Enum.with_index()
      |> Enum.reduce({%{}, ""}, fn {ans, idx}, {opts_acc, correct_acc} ->
        label = Enum.at(letters, idx, "#{idx + 1}")
        text = get_answer_text(ans)

        new_opts = Map.put(opts_acc, label, text)

        new_correct =
          if ans["correct"] == true and correct_acc == "" do
            label
          else
            correct_acc
          end

        {new_opts, new_correct}
      end)

    {opts, correct}
  end

  defp parse_answers(_), do: {%{}, ""}

  defp get_answer_text(%{"content" => c}) when is_binary(c), do: strip_perseus_markup(c)
  defp get_answer_text(%{"text" => t}) when is_binary(t), do: String.trim(t)
  defp get_answer_text(_), do: ""

  # Perseus uses `$...$` for inline math and `$$...$$` for display math.
  # Convert to readable form; strip widget references like `[[☃ image 1]]`.
  defp strip_perseus_markup(text) when is_binary(text) do
    text
    |> String.replace(~r/\[\[\\u2603[^\]]+\]\]/, "")
    |> String.replace(~r/\$\$(.+?)\$\$/s, "[math: \\1]")
    |> String.replace(~r/\$(.+?)\$/s, "\\1")
    |> String.trim()
  end

  defp strip_perseus_markup(_), do: ""

  defp tag_source(q, url, opts) do
    ref = opts[:source_ref] || %{}

    Map.merge(q, %{
      source_url: url,
      source_type: :web_scraped,
      is_generated: false,
      source_page: ref[:source_page],
      metadata: %{"source" => "web_scrape", "extractor" => "khan_academy"},
      grounding_refs: %{"refs" => opts[:grounding_refs] || []}
    })
  end
end
