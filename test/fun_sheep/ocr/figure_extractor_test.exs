defmodule FunSheep.OCR.FigureExtractorTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.OCR.FigureExtractor

  describe "detect_candidates/2" do
    test "detects a table caption" do
      blocks = [
        %{
          text: "Table 2.1: Membrane fatty acid composition by species",
          bounding_box: %{"vertices" => [%{"x" => 10, "y" => 100}, %{"x" => 400, "y" => 200}]}
        }
      ]

      assert [candidate] = FigureExtractor.detect_candidates(blocks, 5)
      assert candidate.figure_type == :table
      assert candidate.figure_number == "2.1"
      assert candidate.caption =~ "Membrane fatty acid composition"
      assert candidate.page_number == 5
    end

    test "detects multiple figure types" do
      blocks = [
        %{text: "Figure 1: cell membrane", bounding_box: %{}},
        %{text: "Table 3: results", bounding_box: %{}},
        %{text: "Graph 2 — temperature", bounding_box: %{}},
        %{text: "Diagram 4: cross-section", bounding_box: %{}}
      ]

      types =
        blocks
        |> FigureExtractor.detect_candidates(1)
        |> Enum.map(& &1.figure_type)
        |> Enum.sort()

      assert types == [:diagram, :figure, :graph, :table]
    end

    test "handles 'Fig. N' abbreviation" do
      blocks = [%{text: "Fig. 7: overview", bounding_box: %{}}]
      assert [%{figure_type: :figure, figure_number: "7"}] =
               FigureExtractor.detect_candidates(blocks, 1)
    end

    test "returns empty list when no captions present" do
      blocks = [
        %{text: "This is just body text.", bounding_box: %{}},
        %{text: "Another paragraph without a caption.", bounding_box: %{}}
      ]

      assert FigureExtractor.detect_candidates(blocks, 1) == []
    end

    test "deduplicates repeated captions" do
      blocks = [
        %{text: "Table 1: overview", bounding_box: %{}},
        %{text: "Table 1: overview", bounding_box: %{}}
      ]

      assert [_single] = FigureExtractor.detect_candidates(blocks, 1)
    end

    test "ignores blocks without text" do
      blocks = [%{bounding_box: %{}}, %{text: nil}]
      assert FigureExtractor.detect_candidates(blocks, 1) == []
    end
  end

  describe "extract_and_store/3" do
    alias FunSheep.Content
    alias FunSheep.ContentFixtures

    setup do
      material = ContentFixtures.create_uploaded_material()

      {:ok, page} =
        Content.create_ocr_page(%{
          material_id: material.id,
          page_number: 1,
          extracted_text: "Table 2.1: data",
          status: :completed
        })

      %{material: material, page: page}
    end

    test "stores figures when captions are detected", %{page: page, material: material} do
      blocks = [%{text: "Table 2.1: counts", bounding_box: %{}}]

      assert {:ok, [figure]} = FigureExtractor.extract_and_store(page, blocks, "fake-image-bytes")
      assert figure.figure_type == :table
      assert figure.figure_number == "2.1"
      assert figure.material_id == material.id
      assert figure.image_path =~ "figures/"
    end

    test "returns [] when no captions", %{page: page} do
      blocks = [%{text: "Body text only", bounding_box: %{}}]
      assert {:ok, []} = FigureExtractor.extract_and_store(page, blocks, "fake")
    end
  end
end
