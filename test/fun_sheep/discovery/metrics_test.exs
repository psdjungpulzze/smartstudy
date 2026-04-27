defmodule FunSheep.Discovery.MetricsTest do
  use ExUnit.Case, async: true

  alias FunSheep.Discovery.Metrics

  describe "metrics/0" do
    test "returns a non-empty list" do
      result = Metrics.metrics()
      assert is_list(result)
      assert length(result) > 0
    end

    test "all items are Telemetry.Metrics structs" do
      result = Metrics.metrics()
      assert Enum.all?(result, &is_struct/1)
    end

    test "includes a counter named 'fun_sheep.discovery.search_complete.count'" do
      result = Metrics.metrics()

      names = Enum.map(result, fn metric -> metric.name end)

      assert Enum.any?(names, fn name ->
               name == [:fun_sheep, :discovery, :search_complete, :count] or
                 name == "fun_sheep.discovery.search_complete.count"
             end)
    end

    test "includes a counter for scraper source_complete" do
      result = Metrics.metrics()

      assert Enum.any?(result, fn metric ->
               name = metric.name

               (is_list(name) and
                  :fun_sheep in name and
                  :scraper in name and
                  :source_complete in name) or
                 (is_binary(name) and String.contains?(name, "scraper") and
                    String.contains?(name, "source_complete"))
             end)
    end

    test "includes expected metric event names covering discovery and scraper" do
      result = Metrics.metrics()

      event_names =
        Enum.map(result, fn metric ->
          case metric do
            %{event_name: event_name} -> event_name
            _ -> []
          end
        end)

      # Verify discovery search events are covered
      assert Enum.any?(event_names, fn name ->
               :fun_sheep in name and :discovery in name and :search_complete in name
             end)

      # Verify scraper source_complete events are covered
      assert Enum.any?(event_names, fn name ->
               :fun_sheep in name and :scraper in name and :source_complete in name
             end)
    end
  end
end
