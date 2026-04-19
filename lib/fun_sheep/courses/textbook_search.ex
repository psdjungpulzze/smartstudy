defmodule FunSheep.Courses.TextbookSearch do
  @moduledoc """
  Searches for textbooks via OpenLibrary API and caches results locally.

  Flow:
  1. Search local DB first
  2. If fewer than 4 local results, supplement with OpenLibrary API
  3. When a user selects an API result, save it to local DB
  """

  alias FunSheep.Courses

  @openlibrary_search_url "https://openlibrary.org/search.json"

  @doc """
  Searches for textbooks matching the given subject and query.
  Combines local DB results with OpenLibrary API results.
  """
  def search(subject, grade \\ nil, query \\ nil) do
    local_results = Courses.search_textbooks(subject, grade, query)

    if length(local_results) >= 4 or (query == nil or query == "") do
      local_results
    else
      api_results = search_openlibrary(subject, query)
      merge_results(local_results, api_results)
    end
  end

  @doc """
  Searches OpenLibrary API and returns a list of textbook-like maps.
  These are NOT yet persisted — they have a temporary structure with
  an `openlibrary_key` that can be used to save them later.
  """
  def search_openlibrary(subject, query) do
    search_term =
      [query, subject]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.join(" ")
      |> String.trim()

    if search_term == "" do
      []
    else
      url =
        "#{@openlibrary_search_url}?" <>
          URI.encode_query(%{
            "q" => search_term,
            "fields" =>
              "key,title,author_name,publisher,edition_count,isbn,cover_i,first_publish_year,subject",
            "limit" => "8",
            "lang" => "en"
          })

      case Req.get(url, receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"docs" => docs}}} ->
          Enum.map(docs, &parse_openlibrary_doc(&1, subject))

        _ ->
          []
      end
    end
  rescue
    _ -> []
  end

  defp parse_openlibrary_doc(doc, subject) do
    cover_id = doc["cover_i"]

    cover_url =
      if cover_id do
        "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"
      end

    isbn =
      case doc["isbn"] do
        [first | _] -> first
        _ -> nil
      end

    %{
      id: nil,
      title: doc["title"] || "Unknown",
      author: (doc["author_name"] || []) |> Enum.take(2) |> Enum.join(", "),
      publisher: (doc["publisher"] || []) |> List.first(),
      edition: edition_text(doc["edition_count"], doc["first_publish_year"]),
      isbn: isbn,
      cover_image_url: cover_url,
      subject: subject,
      grades: [],
      openlibrary_key: doc["key"],
      from_api: true
    }
  end

  defp edition_text(nil, nil), do: nil
  defp edition_text(nil, year), do: "#{year}"
  defp edition_text(count, nil) when count > 1, do: "#{count} editions"
  defp edition_text(_count, year), do: "#{year}"

  defp merge_results(local, api) do
    local_keys = MapSet.new(local, & &1.openlibrary_key)

    new_api =
      api
      |> Enum.reject(fn a ->
        a.openlibrary_key && MapSet.member?(local_keys, a.openlibrary_key)
      end)

    local ++ new_api
  end
end
