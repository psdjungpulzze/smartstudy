defmodule FunSheep.Workers.SourceSitemapCrawlerWorker do
  @moduledoc """
  Oban worker that fetches `sitemap.xml` for a known mid-tier source domain
  and extracts question-page URLs for a given course.

  Enqueued by `WebContentDiscoveryWorker` after the web-search pass for domains
  that publish sitemaps (varsitytutors.com, albert.io, magoosh.com, etc.).

  For each sitemap URL, it:
    1. Fetches and parses the sitemap (or sitemap index → nested sitemaps).
    2. Filters URLs that match section keywords for the course.
    3. Caps at 200 URLs per domain per course to avoid flooding the scraper queue.
    4. Inserts matching URLs as `DiscoveredSource` records with
       `discovery_strategy: "sitemap"`.

  Deduplication is handled by the unique constraint on `(course_id, url)` in
  `discovered_sources`.
  """

  use Oban.Worker, queue: :course_setup, max_attempts: 2

  require Logger

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  alias FunSheep.Content
  alias FunSheep.Courses

  @timeout 15_000
  @max_urls_per_domain 200

  # Domains with well-structured sitemaps worth crawling.
  # format: {domain, sitemap_path, source_type_tag}
  @sitemap_sources [
    {"varsitytutors.com", "/sitemap.xml", "question_bank"},
    {"albert.io", "/sitemap.xml", "question_bank"},
    {"magoosh.com", "/sitemap.xml", "question_bank"},
    {"prepscholar.com", "/sitemap.xml", "question_bank"},
    {"kaplan.com", "/sitemap_index.xml", "question_bank"}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"course_id" => course_id, "domain" => domain}
      }) do
    course = Courses.get_course_with_chapters!(course_id)
    keywords = extract_section_keywords(course)

    Logger.info("[SitemapCrawler] Crawling sitemap for #{domain}, course #{course_id}")

    with {:ok, sitemap_path, source_type} <- find_sitemap_config(domain),
         urls when urls != [] <- fetch_matching_urls(domain, sitemap_path, keywords) do
      stored =
        urls
        |> Enum.take(@max_urls_per_domain)
        |> Enum.reduce(0, fn url, count ->
          attrs = %{
            course_id: course_id,
            source_type: source_type,
            title: build_title(url, domain),
            url: url,
            description: "Discovered via #{domain} sitemap",
            publisher: domain,
            status: "discovered",
            discovery_strategy: "sitemap",
            confidence_score: 0.75
          }

          case Content.create_discovered_source_if_new(attrs) do
            {:ok, %{id: nil}} -> count
            {:ok, _} -> count + 1
            {:error, _} -> count
          end
        end)

      Logger.info("[SitemapCrawler] Stored #{stored} new URLs from #{domain}")
      :ok
    else
      {:error, :unknown_domain} ->
        Logger.debug("[SitemapCrawler] No sitemap config for domain #{domain}")
        :ok

      [] ->
        Logger.debug("[SitemapCrawler] No matching URLs in sitemap for #{domain}")
        :ok

      error ->
        Logger.warning("[SitemapCrawler] Error for #{domain}: #{inspect(error)}")
        :ok
    end
  end

  @doc """
  Enqueues sitemap crawlers for all known domains after a discovery pass.
  Called by `WebContentDiscoveryWorker`.
  """
  def enqueue_for_course(course_id) do
    Enum.each(@sitemap_sources, fn {domain, _path, _type} ->
      %{course_id: course_id, domain: domain}
      |> __MODULE__.new()
      |> Oban.insert()
    end)
  end

  @doc """
  Returns the list of domains this worker knows how to crawl.
  """
  def known_domains, do: Enum.map(@sitemap_sources, fn {d, _, _} -> d end)

  # --- Private ---

  defp find_sitemap_config(domain) do
    case Enum.find(@sitemap_sources, fn {d, _, _} -> d == domain end) do
      {_domain, path, source_type} -> {:ok, path, source_type}
      nil -> {:error, :unknown_domain}
    end
  end

  defp fetch_matching_urls(domain, sitemap_path, keywords) do
    url = "https://#{domain}#{sitemap_path}"

    case fetch_xml(url) do
      {:ok, xml} ->
        all_urls = parse_sitemap_urls(xml)

        # If this is a sitemap index, follow nested sitemaps and collect their URLs.
        all_urls =
          if sitemap_index?(xml) do
            index_urls = parse_sitemap_index_urls(xml)
            filter_by_keyword(index_urls, keywords)
            |> Enum.take(5)
            |> Enum.flat_map(fn nested_url ->
              case fetch_xml(nested_url) do
                {:ok, nested_xml} -> parse_sitemap_urls(nested_xml)
                _ -> []
              end
            end)
          else
            all_urls
          end

        filter_by_keyword(all_urls, keywords)

      {:error, reason} ->
        Logger.warning("[SitemapCrawler] Could not fetch sitemap #{url}: #{inspect(reason)}")
        []
    end
  end

  defp fetch_xml(url) do
    case Req.get(url,
           receive_timeout: @timeout,
           max_redirects: 5,
           retry: false,
           finch: FunSheep.Finch
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: s}} -> {:error, {:http, s}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :exception}
  end

  defp sitemap_index?(xml) when is_binary(xml) do
    String.contains?(xml, "<sitemapindex") or String.contains?(xml, "<sitemap>")
  end

  defp parse_sitemap_urls(xml) when is_binary(xml) do
    try do
      xml
      |> xpath(~x"//url/loc/text()"ls)
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp parse_sitemap_index_urls(xml) when is_binary(xml) do
    try do
      xml
      |> xpath(~x"//sitemap/loc/text()"ls)
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    end
  end

  defp filter_by_keyword(urls, []) do
    # No keywords = no filtering (happens for courses with no sections yet).
    Enum.take(urls, @max_urls_per_domain)
  end

  defp filter_by_keyword(urls, keywords) do
    downcase_keywords = Enum.map(keywords, &String.downcase/1)

    Enum.filter(urls, fn url ->
      lower = String.downcase(url)
      Enum.any?(downcase_keywords, fn kw -> String.contains?(lower, kw) end)
    end)
  end

  defp extract_section_keywords(%{chapters: chapters}) do
    chapters
    |> Enum.flat_map(fn chapter ->
      chapter_kw = chapter.name |> clean_name() |> String.split()
      section_kws = Enum.flat_map(chapter.sections || [], fn s ->
        s.name |> clean_name() |> String.split()
      end)

      chapter_kw ++ section_kws
    end)
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
  end

  defp clean_name(name) when is_binary(name) do
    name
    |> String.replace(~r/^(Chapter|Unit|Section)\s*\d+\s*[:\-]?\s*/i, "")
    |> String.downcase()
    |> String.trim()
  end

  defp clean_name(_), do: ""

  defp build_title(url, domain) do
    uri = URI.parse(url)
    path = uri.path || ""

    path
    |> String.split("/")
    |> List.last()
    |> then(fn slug ->
      if is_binary(slug) and slug != "" do
        slug
        |> String.replace(~r/[-_]/, " ")
        |> String.replace(~r/\.\w+$/, "")
        |> String.trim()
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
      else
        domain
      end
    end)
  end
end
