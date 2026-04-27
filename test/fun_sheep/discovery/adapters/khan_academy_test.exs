defmodule FunSheep.Discovery.Adapters.KhanAcademyTest do
  use ExUnit.Case, async: true

  alias FunSheep.Discovery.Adapters.KhanAcademy

  # Simulates the JSON body shape of the KA exercises API
  defp exercises_response(count) do
    exercises =
      for i <- 1..count do
        %{
          "name" => "exercise-#{i}",
          "display_name" => "Exercise #{i}",
          "description" => "Practice exercise #{i}",
          "ka_url" => "/e/exercise-#{i}"
        }
      end

    %{"exercises" => exercises}
  end

  defp ok_http(body) do
    fn _url -> {:ok, %{status: 200, body: body}} end
  end

  describe "discover/3" do
    test "returns exercise URLs for known SAT math slug" do
      results =
        KhanAcademy.discover("sat", "mathematics",
          http_fn: ok_http(exercises_response(10))
        )

      assert length(results) == 10
      assert Enum.all?(results, &String.starts_with?(&1.url, "https://www.khanacademy.org"))
      assert Enum.all?(results, &(&1.source_type == "question_bank"))
      assert Enum.all?(results, &(&1.discovery_strategy == "api_adapter"))
      assert Enum.all?(results, &(&1.publisher == "khanacademy.org"))
    end

    test "returns [] for unknown test type" do
      results = KhanAcademy.discover("unknown_test", nil)
      assert results == []
    end

    test "returns [] when API returns non-200" do
      http_fn = fn _url -> {:ok, %{status: 404, body: %{}}} end
      results = KhanAcademy.discover("sat", "mathematics", http_fn: http_fn)
      assert results == []
    end

    test "returns [] when API call errors" do
      http_fn = fn _url -> {:error, :timeout} end
      results = KhanAcademy.discover("sat", "mathematics", http_fn: http_fn)
      assert results == []
    end

    test "handles API body with no exercises key" do
      http_fn = ok_http(%{})
      results = KhanAcademy.discover("sat", "mathematics", http_fn: http_fn)
      assert results == []
    end

    test "supports AP Biology slug" do
      results =
        KhanAcademy.discover("ap_biology", nil,
          http_fn: ok_http(exercises_response(5))
        )

      assert length(results) == 5
    end

    test "result URLs contain khanacademy.org and the exercise path" do
      results =
        KhanAcademy.discover("sat", "mathematics",
          http_fn: ok_http(exercises_response(3))
        )

      for r <- results do
        assert r.url =~ "khanacademy.org"
        assert r.url =~ "/e/exercise-"
      end
    end
  end
end
