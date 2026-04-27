defmodule FunSheep.Scraper.Extractors.Generic do
  @moduledoc """
  Fallback extractor: wraps `FunSheep.Questions.Extractor` AI path.

  Used for any URL that has no site-specific extractor. Parses the HTML
  with `HtmlParser` first so the AI receives structured text rather than
  raw HTML soup, then delegates to the existing LLM extraction logic.
  """

  alias FunSheep.Questions.Extractor
  alias FunSheep.Scraper.HtmlParser

  @doc false
  def extract(html, _url, opts) when is_binary(html) do
    text = HtmlParser.parse(html)

    questions =
      Extractor.extract(text,
        subject: opts[:subject],
        source: :web,
        source_ref: opts[:source_ref] || %{},
        grounding_refs: opts[:grounding_refs] || [],
        test_type: opts[:test_type],
        section_hint: opts[:section_hint]
      )

    {:ok, questions}
  end
end
