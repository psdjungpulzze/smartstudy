defmodule FunSheep.Discovery.Adapters.CollegeBoardTest do
  use ExUnit.Case, async: true

  alias FunSheep.Discovery.Adapters.CollegeBoard

  defp ok_probe(_url), do: :ok
  defp reject_probe(_url), do: {:error, {:http, 404}}

  describe "discover/3" do
    test "returns 8 official practice test URLs for SAT" do
      results = CollegeBoard.discover("sat", nil, probe_fn: &ok_probe/1)

      assert length(results) == 8
      assert Enum.all?(results, &(&1.source_type == "practice_test"))
      assert Enum.all?(results, &(&1.publisher == "collegeboard.org"))
      assert Enum.all?(results, &(&1.discovery_strategy == "api_adapter"))
      assert Enum.all?(results, &String.contains?(&1.url, "collegeboard.org"))
      assert Enum.all?(results, &String.ends_with?(&1.url, ".pdf"))
    end

    test "SAT practice test URLs are numbered 1 through 8" do
      results = CollegeBoard.discover("sat", nil, probe_fn: &ok_probe/1)
      urls = Enum.map(results, & &1.url)

      for n <- 1..8 do
        assert Enum.any?(urls, &String.contains?(&1, "practice-test-#{n}.pdf")),
               "Missing practice test #{n}"
      end
    end

    test "drops URLs that fail the probe" do
      results = CollegeBoard.discover("sat", nil, probe_fn: &reject_probe/1)
      assert results == []
    end

    test "returns AP FRQ PDFs for known AP subjects" do
      results = CollegeBoard.discover("ap_biology", nil, probe_fn: &ok_probe/1)

      assert length(results) > 0
      assert Enum.all?(results, &String.contains?(&1.url, "apcentral.collegeboard.org"))
      assert Enum.all?(results, &String.ends_with?(&1.url, ".pdf"))
    end

    test "AP FRQ results include multiple years" do
      results = CollegeBoard.discover("ap_chemistry", nil, probe_fn: &ok_probe/1)
      urls = Enum.map(results, & &1.url)

      assert Enum.any?(urls, &String.contains?(&1, "2024"))
      assert Enum.any?(urls, &String.contains?(&1, "2023"))
    end

    test "returns [] for unknown test type" do
      results = CollegeBoard.discover("unknown_test", nil, probe_fn: &ok_probe/1)
      assert results == []
    end

    test "confidence is >= 0.95 for official sources" do
      results = CollegeBoard.discover("sat", nil, probe_fn: &ok_probe/1)
      assert Enum.all?(results, &(&1.confidence >= 0.95))
    end
  end
end
