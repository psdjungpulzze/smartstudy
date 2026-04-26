defmodule FunSheep.Scraper.HtmlParser do
  @moduledoc """
  Structured HTML → plain-text converter using Floki.

  The old `strip_html/1` regex approach lost structure that matters for
  question extraction: numbered MCQ options, math notation, and tables.
  This module uses Floki's DOM parser to:

    - Extract only content-bearing sections (`<main>`, `[role=main]`,
      `<article>`, or `<body>` as fallback).
    - Strip noise: `<nav>`, `<header>`, `<footer>`, `<script>`, `<style>`,
      `.advertisement`, `[aria-hidden]`, cookie banners.
    - Preserve `<ol>/<li>` as "1. item" numbered lines (MCQ options).
    - Preserve `<ul>/<li>` as "• item" bullet lines.
    - Render `<table>` as tab-separated rows with headers.
    - Preserve MathJax spans and LaTeX `\(...\)` / `\[...\]` as-is.

  Returns a plain-text string ready for question extraction.
  """

  @noise_selectors ~w(
    nav
    header
    footer
    script
    style
    .advertisement
    .ads
    .sidebar
    .cookie-banner
    .social-share
    [aria-hidden=true]
    [role=navigation]
    [role=banner]
    [role=contentinfo]
  )

  @doc """
  Parse HTML into structured plain text suitable for question extraction.
  Returns `""` on parse failure (never raises).
  """
  @spec parse(String.t()) :: String.t()
  def parse(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> extract_content_node()
        |> remove_noise()
        |> node_to_text()
        |> collapse_whitespace()

      {:error, _} ->
        fallback_strip(html)
    end
  rescue
    _ -> fallback_strip(html)
  end

  def parse(_), do: ""

  # --- Content extraction ---

  defp extract_content_node(document) do
    # Prefer semantic content containers over the full document
    case Floki.find(document, "main, [role=main], article") do
      [node | _] -> node
      [] ->
        case Floki.find(document, "body") do
          [body | _] -> body
          [] -> document
        end
    end
  end

  defp remove_noise(node) do
    Enum.reduce(@noise_selectors, node, fn selector, acc ->
      Floki.filter_out(acc, selector)
    end)
  end

  # --- Node → text rendering ---

  defp node_to_text(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&node_to_text/1)
    |> Enum.join("")
  end

  defp node_to_text({"ol", _attrs, children}) do
    children
    |> Enum.filter(&li?/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {li, idx} -> "#{idx}. #{li_text(li)}\n" end)
    |> Enum.join("")
    |> then(&(&1 <> "\n"))
  end

  defp node_to_text({"ul", _attrs, children}) do
    children
    |> Enum.filter(&li?/1)
    |> Enum.map(fn li -> "• #{li_text(li)}\n" end)
    |> Enum.join("")
    |> then(&(&1 <> "\n"))
  end

  defp node_to_text({"table", _attrs, children}) do
    rows = Floki.find(children, "tr")

    rows
    |> Enum.map(fn row ->
      cells =
        Floki.find(row, "th, td")
        |> Enum.map(&(Floki.text(&1) |> String.trim()))

      Enum.join(cells, "\t")
    end)
    |> Enum.join("\n")
    |> then(&(&1 <> "\n\n"))
  end

  # MathJax inline/display — preserve the raw LaTeX text
  defp node_to_text({"script", [{"type", "math/tex" <> _}], children}) do
    "\\(" <> Floki.text(children) <> "\\) "
  end

  # Block-level elements: add newlines around content
  defp node_to_text({tag, _attrs, children})
       when tag in ~w(p div section h1 h2 h3 h4 h5 h6 blockquote) do
    inner = node_to_text(children)

    if String.trim(inner) == "" do
      ""
    else
      "\n" <> inner <> "\n"
    end
  end

  # Line breaks
  defp node_to_text({"br", _, _}), do: "\n"

  # Inline elements — just recurse
  defp node_to_text({_tag, _attrs, children}), do: node_to_text(children)

  # Text nodes
  defp node_to_text(text) when is_binary(text) do
    # Preserve LaTeX delimiters that appear as raw text
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
  end

  defp node_to_text(_), do: ""

  defp li?({tag, _, _}) when tag in ["li"], do: true
  defp li?(_), do: false

  defp li_text({"li", _, children}), do: node_to_text(children) |> String.trim()
  defp li_text(node), do: Floki.text(node) |> String.trim()

  defp collapse_whitespace(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end

  # Regex fallback when Floki fails to parse
  defp fallback_strip(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/si, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/si, "")
    |> String.replace(~r/<nav[^>]*>.*?<\/nav>/si, "")
    |> String.replace(~r/<footer[^>]*>.*?<\/footer>/si, "")
    |> String.replace(~r/<header[^>]*>.*?<\/header>/si, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
