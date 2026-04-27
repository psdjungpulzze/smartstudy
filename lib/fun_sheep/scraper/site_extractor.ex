defmodule FunSheep.Scraper.SiteExtractor do
  @moduledoc """
  Dispatch module: routes HTML extraction to the right site-specific extractor.

  Maps host names to dedicated extractors that use DOM parsing or JSON blobs
  instead of the generic AI path. Unknown hosts fall through to `Generic`,
  which wraps the existing `FunSheep.Questions.Extractor` AI path.

  All extractor modules implement:
    `extract(html, url, opts) :: {:ok, [question_map()]} | {:error, term()}`

  `opts` may include:
    `:subject`      — course subject string for AI context
    `:test_type`    — catalog_test_type atom/string (e.g. "sat", "ap_biology")
    `:section_hint` — section name for AI context (e.g. "Heart of Algebra")
    `:grounding_refs` — provenance refs for each question
    `:source_ref`   — %{source_url:, source_title:, ...}
  """

  alias FunSheep.Scraper.Extractors

  # Maps host patterns (exact or suffix match) → extractor module.
  # Order matters: more-specific patterns should come first if ambiguity arises.
  @extractors [
    {"khanacademy.org", Extractors.KhanAcademy},
    {"varsitytutors.com", Extractors.VarsityTutors},
    {"albert.io", Extractors.Albert},
    {"collegeboard.org", Extractors.CollegeBoard},
    {"satsuite.collegeboard.org", Extractors.CollegeBoard}
  ]

  @doc """
  Extract questions from `html` fetched from `url`.
  Dispatches to the appropriate site-specific extractor, falling back to Generic.
  """
  @spec extract(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def extract(html, url, opts \\ []) when is_binary(html) and is_binary(url) do
    module = dispatcher_for(url)
    module.extract(html, url, opts)
  end

  @doc """
  Returns the extractor module that would handle the given URL.
  Useful for telemetry and testing.
  """
  @spec extractor_for(String.t()) :: module()
  def extractor_for(url), do: dispatcher_for(url)

  defp dispatcher_for(url) do
    host =
      case URI.parse(url) do
        %URI{host: h} when is_binary(h) -> String.downcase(h) |> String.replace_prefix("www.", "")
        _ -> ""
      end

    @extractors
    |> Enum.find(fn {pattern, _mod} ->
      host == pattern or String.ends_with?(host, "." <> pattern)
    end)
    |> case do
      {_, mod} -> mod
      nil -> Extractors.Generic
    end
  end
end
