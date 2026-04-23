defmodule FunSheep.Workers.EnrichDiscoveryWorkerTest do
  use ExUnit.Case, async: true

  alias FunSheep.Workers.EnrichDiscoveryWorker

  defp mat(name), do: %{file_name: name}

  describe "extract_filename_chapter_numbers/1" do
    test "pulls distinct chapter numbers from 'Biology Chapter N - M.jpg' style filenames" do
      materials =
        for ch <- [1, 2, 3, 14, 39], page <- 1..3 do
          mat("Biology Chapter #{ch} - #{page}.jpg")
        end

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) ==
               [1, 2, 3, 14, 39]
    end

    test "matches unit/module/part variants and is case-insensitive" do
      materials = [
        mat("Unit 4 Notes.pdf"),
        mat("module 7 slides.png"),
        mat("PART 12 - overview.jpg")
      ]

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) == [4, 7, 12]
    end

    test "returns [] when filenames don't contain the pattern" do
      materials = [
        mat("scan-001.jpg"),
        mat("IMG_4821.png"),
        mat("biology book pg 4.jpg")
      ]

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) == []
    end

    test "ignores hits that are out of the plausible range" do
      materials = [
        mat("Chapter 0 - intro.jpg"),
        mat("Chapter 1500 - wild.jpg"),
        mat("Chapter 5 - real.jpg")
      ]

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) == [5]
    end

    test "tolerates nil and non-binary file_names without crashing" do
      materials = [mat(nil), mat("Chapter 3 - ok.jpg"), %{file_name: :weird}]

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) == [3]
    end

    test "handles whitespace variations (Chapter  12, chapter12)" do
      materials = [
        mat("Chapter   12 - a.jpg"),
        mat("chapter12 - b.jpg")
      ]

      assert EnrichDiscoveryWorker.extract_filename_chapter_numbers(materials) == [12]
    end
  end
end
