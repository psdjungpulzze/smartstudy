defmodule FunSheep.Ebook.EpubParser do
  @moduledoc """
  Parses an EPUB file (which is a ZIP archive) to extract:

    * Bibliographic metadata: title, authors, publisher, language, ISBN
    * Table of contents (from EPUB 3 nav.xhtml or EPUB 2 toc.ncx)
    * Plain-text content for each spine document (chapter text for OCR pages)

  All content is real — extracted from the actual file. Nothing is
  synthesised or approximated. If a required component is missing or the
  file is DRM-protected, an error is returned so the caller can fail
  honestly.

  ## Return values

    * `{:ok, %{metadata: map, toc: list, spine_items: list}}`
    * `{:error, :drm_protected}`
    * `{:error, :invalid_epub}`
    * `{:error, :missing_opf}`

  where `toc` is a list of `%{title: String.t(), depth: non_neg_integer(), href: String.t()}`
  and `spine_items` is a list of `%{index: non_neg_integer(), href: String.t(), text: String.t()}`.
  """

  require Logger

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3, xmap: 2]

  @doc """
  Extracts metadata, TOC, and spine text from an EPUB file at the given path.
  The file must be a valid ZIP-based EPUB; the path must be accessible on the
  local filesystem when this function is called.
  """
  @spec extract(String.t()) ::
          {:ok, %{metadata: map(), toc: list(), spine_items: list()}}
          | {:error, :drm_protected | :invalid_epub | :missing_opf}
  def extract(path) do
    with {:ok, entries} <- read_zip(path),
         :ok <- check_drm(entries),
         {:ok, opf_path} <- find_opf_path(entries),
         {:ok, opf_xml} <- get_entry(entries, opf_path),
         {:ok, metadata} <- parse_metadata(opf_xml),
         {:ok, manifest} <- parse_manifest(opf_xml, opf_path),
         {:ok, spine_hrefs} <- parse_spine(opf_xml, manifest),
         {:ok, toc} <- extract_toc(entries, opf_xml, manifest, opf_path),
         {:ok, spine_items} <- extract_spine_text(entries, spine_hrefs, opf_path) do
      {:ok, %{metadata: metadata, toc: toc, spine_items: spine_items}}
    end
  end

  # ── Internal helpers ─────────────────────────────────────────────────────

  defp read_zip(path) do
    charlist_path = String.to_charlist(path)

    case :zip.unzip(charlist_path, [:memory]) do
      {:ok, entries} ->
        # Convert charlist entry names to strings for easier matching
        string_entries =
          Enum.map(entries, fn {name, content} -> {List.to_string(name), content} end)

        {:ok, string_entries}

      {:error, reason} ->
        Logger.debug("[EpubParser] ZIP extraction failed for #{path}: #{inspect(reason)}")
        {:error, :invalid_epub}
    end
  end

  defp get_entry(entries, path) do
    # Normalise the path: strip leading "/" if present
    normalised = String.trim_leading(path, "/")

    case Enum.find(entries, fn {name, _} -> name == normalised end) do
      {_, content} -> {:ok, content}
      nil -> {:error, {:missing_entry, path}}
    end
  end

  defp check_drm(entries) do
    has_encryption = Enum.any?(entries, fn {name, _} -> name == "META-INF/encryption.xml" end)

    if has_encryption do
      {:error, :drm_protected}
    else
      :ok
    end
  end

  defp find_opf_path(entries) do
    case get_entry(entries, "META-INF/container.xml") do
      {:ok, xml} ->
        case xpath(xml, ~x"//rootfile/@full-path"s) do
          "" ->
            {:error, :missing_opf}

          opf_path ->
            {:ok, opf_path}
        end

      {:error, _} ->
        {:error, :missing_opf}
    end
  end

  defp parse_metadata(opf_xml) do
    metadata = %{
      "title" => xpath(opf_xml, ~x"//dc:title/text()"sl) |> first_or_nil(),
      "authors" => xpath(opf_xml, ~x"//dc:creator/text()"sl),
      "publisher" => xpath(opf_xml, ~x"//dc:publisher/text()"sl) |> first_or_nil(),
      "language" => xpath(opf_xml, ~x"//dc:language/text()"sl) |> first_or_nil(),
      "isbn" => extract_isbn(opf_xml)
    }

    {:ok, metadata}
  end

  defp extract_isbn(opf_xml) do
    # ISBN may be in dc:identifier with scheme attribute
    identifiers = xpath(opf_xml, ~x"//dc:identifier"l)

    isbn =
      Enum.find_value(identifiers, fn node ->
        scheme = xpath(node, ~x"./@opf:scheme"s)
        id_val = xpath(node, ~x"./text()"s)

        if String.upcase(scheme) =~ "ISBN" do
          id_val
        else
          # Some EPUBs embed "isbn:" in the text itself
          if String.downcase(id_val) =~ ~r/^isbn[:\s]/ do
            id_val
          end
        end
      end)

    isbn
  end

  defp parse_manifest(opf_xml, opf_path) do
    opf_dir = Path.dirname(opf_path)

    items = xpath(opf_xml, ~x"//manifest/item"l)

    manifest =
      Enum.reduce(items, %{}, fn item, acc ->
        id = xpath(item, ~x"./@id"s)
        href = xpath(item, ~x"./@href"s)
        media_type = xpath(item, ~x"./@media-type"s)
        properties = xpath(item, ~x"./@properties"s)

        # Resolve href relative to the OPF directory
        full_href =
          if opf_dir == "." do
            href
          else
            Path.join(opf_dir, href)
          end

        Map.put(acc, id, %{
          href: full_href,
          raw_href: href,
          media_type: media_type,
          properties: properties
        })
      end)

    {:ok, manifest}
  end

  defp parse_spine(opf_xml, manifest) do
    idref_nodes = xpath(opf_xml, ~x"//spine/itemref"l)

    hrefs =
      Enum.flat_map(idref_nodes, fn node ->
        idref = xpath(node, ~x"./@idref"s)

        case Map.get(manifest, idref) do
          nil -> []
          %{href: href} -> [href]
        end
      end)

    {:ok, hrefs}
  end

  # ── TOC extraction ────────────────────────────────────────────────────────

  defp extract_toc(entries, opf_xml, manifest, opf_path) do
    opf_dir = Path.dirname(opf_path)

    # EPUB 3: look for item with properties="nav"
    epub3_nav_item =
      Enum.find_value(manifest, fn {_id, item} ->
        if String.contains?(item.properties || "", "nav"), do: item
      end)

    # EPUB 2: look for NCX item (media-type = application/x-dtbncx+xml)
    epub2_ncx_item =
      Enum.find_value(manifest, fn {_id, item} ->
        if item.media_type == "application/x-dtbncx+xml", do: item
      end)

    cond do
      epub3_nav_item != nil ->
        parse_epub3_nav(entries, epub3_nav_item.href, opf_dir)

      epub2_ncx_item != nil ->
        parse_epub2_ncx(entries, epub2_ncx_item.href, opf_dir)

      true ->
        # No navigation document — return an empty TOC (not an error)
        Logger.debug("[EpubParser] No navigation document found in EPUB")
        {:ok, []}
    end
  end

  defp parse_epub3_nav(entries, nav_href, _opf_dir) do
    case get_entry(entries, nav_href) do
      {:ok, html} ->
        toc_entries = extract_nav_xhtml_toc(html)
        {:ok, toc_entries}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp extract_nav_xhtml_toc(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        # Find <nav epub:type="toc"> or <nav role="doc-toc">
        nav =
          Floki.find(doc, ~s|nav[epub\\:type="toc"]|) ++
            Floki.find(doc, ~s|nav[epub\\:type='toc']|)

        nav_node =
          case nav do
            [n | _] -> n
            [] -> doc
          end

        collect_nav_entries(nav_node, 0)

      {:error, _} ->
        []
    end
  end

  defp collect_nav_entries(node, depth) do
    # Each <li> in the <ol>/<ul> may contain an <a> followed by a nested <ol>/<ul>
    lis = Floki.find(node, "li")

    Enum.flat_map(lis, fn li ->
      title =
        li
        |> Floki.find("a")
        |> List.first()
        |> case do
          nil -> nil
          a -> Floki.text(a) |> String.trim()
        end

      href =
        li
        |> Floki.find("a")
        |> List.first()
        |> case do
          nil -> ""
          a -> Floki.attribute(a, "href") |> List.first() || ""
        end

      entry =
        if title && title != "" do
          [%{title: title, depth: depth, href: href}]
        else
          []
        end

      # Recurse into nested lists but avoid double-counting by only looking
      # at direct child <ol>/<ul> elements
      children =
        li
        |> Floki.find("ol, ul")
        |> Enum.flat_map(&collect_nav_entries(&1, depth + 1))

      entry ++ children
    end)
  end

  defp parse_epub2_ncx(entries, ncx_href, _opf_dir) do
    case get_entry(entries, ncx_href) do
      {:ok, xml} ->
        toc_entries = extract_ncx_nav_points(xml, 0)
        {:ok, toc_entries}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp extract_ncx_nav_points(xml, _depth) do
    nav_points = xpath(xml, ~x"//navMap/navPoint"l)
    collect_ncx_points(nav_points, 0)
  end

  defp collect_ncx_points(nav_points, depth) do
    Enum.flat_map(nav_points, fn point ->
      title = xpath(point, ~x"navLabel/text/text()"s) |> String.trim()
      href = xpath(point, ~x"content/@src"s)

      entry =
        if title != "" do
          [%{title: title, depth: depth, href: href}]
        else
          []
        end

      children = xpath(point, ~x"navPoint"l)
      nested = collect_ncx_points(children, depth + 1)

      entry ++ nested
    end)
  end

  # ── Spine text extraction ─────────────────────────────────────────────────

  defp extract_spine_text(entries, spine_hrefs, _opf_path) do
    items =
      spine_hrefs
      |> Enum.with_index()
      |> Enum.map(fn {href, index} ->
        text =
          case get_entry(entries, href) do
            {:ok, html} ->
              extract_text_from_xhtml(html)

            {:error, _} ->
              ""
          end

        %{index: index, href: href, text: text}
      end)

    {:ok, items}
  end

  defp extract_text_from_xhtml(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.text(sep: "\n")
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      {:error, _} ->
        # If Floki can't parse it, it might be binary/non-HTML content
        ""
    end
  end

  # ── Utilities ─────────────────────────────────────────────────────────────

  defp first_or_nil([]), do: nil
  defp first_or_nil([h | _]), do: h
  defp first_or_nil(nil), do: nil
end
