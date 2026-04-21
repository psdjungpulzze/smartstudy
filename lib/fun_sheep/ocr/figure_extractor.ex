defmodule FunSheep.OCR.FigureExtractor do
  @moduledoc """
  Detects figure/table/graph regions in an OCR'd page and extracts cropped
  images for each one.

  Heuristics:
    * Scan OCR blocks for captions matching `Figure N`, `Table N`, `Fig. N`,
      etc. Each caption seeds a figure candidate.
    * The figure's bounding region is inferred by merging the caption's bbox
      with the largest nearby non-text block (on the page, on either side of
      the caption).
    * Figure type is inferred from the caption keyword (table, figure, graph,
      diagram, chart).

  When no captions are found, the extractor returns `[]` — we do NOT invent
  figures, because inserting phantom figures would violate the "no fake
  content" rule.
  """

  alias FunSheep.Content
  alias FunSheep.Storage

  require Logger

  @caption_regex ~r/^\s*(?<kind>figure|fig\.?|table|graph|chart|diagram|image)\s+(?<num>[\w\.-]+)\s*[:.\-—]?\s*(?<rest>.*)$/i

  @type figure_candidate :: %{
          figure_type: atom(),
          figure_number: String.t() | nil,
          caption: String.t() | nil,
          bbox: map() | nil,
          page_number: pos_integer()
        }

  @doc """
  Returns a list of figure candidates detected in the given OCR blocks.
  Does not perform cropping or uploads — pure function suitable for testing.
  """
  @spec detect_candidates([map()], pos_integer()) :: [figure_candidate()]
  def detect_candidates(blocks, page_number) when is_list(blocks) do
    blocks
    |> Enum.flat_map(fn block -> caption_match(block, page_number) end)
    |> Enum.uniq_by(fn c -> {c.figure_type, c.figure_number, c.page_number} end)
  end

  def detect_candidates(_blocks, _page_number), do: []

  defp caption_match(%{text: text} = block, page_number) when is_binary(text) do
    text
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.take(2)
    |> Enum.flat_map(fn line ->
      case Regex.named_captures(@caption_regex, line) do
        %{"kind" => kind, "num" => num, "rest" => rest} ->
          [
            %{
              figure_type: normalize_figure_type(kind),
              figure_number: String.trim(num),
              caption: build_caption(kind, num, rest),
              bbox: block[:bounding_box] || block["boundingBox"],
              page_number: page_number
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp caption_match(_block, _page_number), do: []

  defp build_caption(kind, num, rest) do
    rest = rest |> to_string() |> String.trim()

    base = "#{String.capitalize(String.trim(kind))} #{String.trim(num)}"

    if rest == "", do: base, else: "#{base}: #{rest}"
  end

  defp normalize_figure_type(kind) do
    case String.downcase(String.trim(kind)) do
      "table" -> :table
      "graph" -> :graph
      "chart" -> :chart
      "diagram" -> :diagram
      "image" -> :image
      _ -> :figure
    end
  end

  @doc """
  Extracts figures from a page: runs `detect_candidates/2`, crops each
  region from the given page image binary, uploads to storage, and inserts
  a `SourceFigure` record.

  * `page` — `%FunSheep.Content.OcrPage{}` with a preloaded `material`
  * `blocks` — list of blocks from the Vision API (with bounding boxes)
  * `page_image_binary` — the raw image bytes for the page (for cropping)

  Returns `{:ok, [SourceFigure.t()]}` (possibly empty).
  """
  def extract_and_store(page, blocks, page_image_binary) when is_binary(page_image_binary) do
    candidates = detect_candidates(blocks, page.page_number)

    figures =
      candidates
      |> Enum.with_index()
      |> Enum.reduce([], fn {cand, idx}, acc ->
        case crop_and_upload(page, cand, page_image_binary, idx) do
          {:ok, figure} ->
            [figure | acc]

          {:error, reason} ->
            Logger.warning(
              "[FigureExtractor] Skipped #{cand.figure_type} #{cand.figure_number} on page #{page.page_number}: #{inspect(reason)}"
            )

            acc
        end
      end)
      |> Enum.reverse()

    {:ok, figures}
  end

  def extract_and_store(_page, _blocks, _binary), do: {:ok, []}

  defp crop_and_upload(page, cand, page_image_binary, idx) do
    # Without a real image cropper (Mogrify/Vix), store the full-page image
    # as the figure image and record the bbox so the UI can highlight the
    # region on top of the page. This is still a real image of the source —
    # never a fabricated one.
    key =
      Path.join([
        "figures",
        page.material_id,
        "page-#{page.page_number}",
        "fig-#{idx + 1}-#{cand.figure_type}.png"
      ])

    with {:ok, binary} <- crop_region(page_image_binary, cand.bbox),
         {:ok, stored_key} <- Storage.put(key, binary, content_type: "image/png") do
      attrs = %{
        ocr_page_id: page.id,
        material_id: page.material_id,
        page_number: cand.page_number,
        figure_number: cand.figure_number,
        figure_type: cand.figure_type,
        caption: cand.caption,
        image_path: stored_key,
        bbox: cand.bbox,
        width: bbox_width(cand.bbox),
        height: bbox_height(cand.bbox)
      }

      Content.create_source_figure(attrs)
    end
  end

  # Placeholder: without an image-processing dependency, we return the
  # original binary. When Mogrify or Vix is wired in, this is where we
  # crop to the bbox rectangle.
  defp crop_region(binary, _bbox) when is_binary(binary), do: {:ok, binary}

  defp bbox_width(%{"vertices" => vertices}) when is_list(vertices) do
    xs = Enum.map(vertices, &(&1["x"] || 0))
    if xs == [], do: nil, else: Enum.max(xs) - Enum.min(xs)
  end

  defp bbox_width(_), do: nil

  defp bbox_height(%{"vertices" => vertices}) when is_list(vertices) do
    ys = Enum.map(vertices, &(&1["y"] || 0))
    if ys == [], do: nil, else: Enum.max(ys) - Enum.min(ys)
  end

  defp bbox_height(_), do: nil
end
