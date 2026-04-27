defmodule FunSheep.Workers.SourceRegistryVerifierWorkerTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.{Repo}
  alias FunSheep.Discovery.SourceRegistryEntry
  alias FunSheep.Workers.SourceRegistryVerifierWorker

  defp insert_entry(attrs \\ %{}) do
    defaults = %{
      test_type: "sat",
      catalog_subject: nil,
      url_or_pattern: "https://example.com/#{:erlang.unique_integer([:positive])}",
      domain: "example.com",
      source_type: "practice_test",
      tier: 2,
      is_enabled: true,
      consecutive_failures: 0
    }

    Repo.insert!(
      %SourceRegistryEntry{}
      |> SourceRegistryEntry.changeset(Map.merge(defaults, attrs))
    )
  end

  defp stale_entry(attrs \\ %{}) do
    insert_entry(Map.merge(%{last_verified_at: ~U[2020-01-01 00:00:00Z]}, attrs))
  end

  defp ok_probe, do: fn _url -> :ok end
  defp fail_probe(reason \\ :timeout), do: fn _url -> {:error, reason} end

  describe "run/1 with injected probe" do
    test "resets consecutive_failures and records last_verified_at on success" do
      entry = stale_entry(%{consecutive_failures: 2})

      SourceRegistryVerifierWorker.run(probe_fn: ok_probe())

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.consecutive_failures == 0
      assert updated.last_verified_at != nil
    end

    test "increments consecutive_failures on probe failure" do
      entry = stale_entry(%{consecutive_failures: 0})

      SourceRegistryVerifierWorker.run(probe_fn: fail_probe())

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.consecutive_failures == 1
      assert updated.is_enabled == true
    end

    test "disables entry after 3 consecutive failures" do
      entry = stale_entry(%{consecutive_failures: 2})

      SourceRegistryVerifierWorker.run(probe_fn: fail_probe({:http_status, 404}))

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.consecutive_failures == 3
      assert updated.is_enabled == false
    end

    test "does not disable entry before reaching the failure threshold" do
      entry = stale_entry(%{consecutive_failures: 1})

      SourceRegistryVerifierWorker.run(probe_fn: fail_probe())

      updated = Repo.get!(SourceRegistryEntry, entry.id)
      assert updated.consecutive_failures == 2
      assert updated.is_enabled == true
    end

    test "skips entries verified recently (within 7 days)" do
      _recent = insert_entry(%{last_verified_at: DateTime.utc_now(), consecutive_failures: 5})
      stale = stale_entry(%{consecutive_failures: 0})

      called_urls = Agent.start_link(fn -> [] end) |> elem(1)
      probe = fn url -> Agent.update(called_urls, fn urls -> [url | urls] end); :ok end

      SourceRegistryVerifierWorker.run(probe_fn: probe)

      probed = Agent.get(called_urls, & &1)
      Agent.stop(called_urls)

      # Only the stale entry's URL should have been probed
      assert length(probed) == 1
      assert hd(probed) == stale.url_or_pattern
    end

    test "skips disabled entries entirely" do
      stale_entry(%{is_enabled: false, consecutive_failures: 2})

      called = Agent.start_link(fn -> 0 end) |> elem(1)
      probe = fn _url -> Agent.update(called, &(&1 + 1)); :ok end

      SourceRegistryVerifierWorker.run(probe_fn: probe)

      assert Agent.get(called, & &1) == 0
      Agent.stop(called)
    end

    test "handles multiple entries independently" do
      stale1 = stale_entry(%{consecutive_failures: 0})
      stale2 = stale_entry(%{consecutive_failures: 2})

      # stale1 succeeds, stale2 fails
      probe = fn url ->
        if url == stale1.url_or_pattern, do: :ok, else: {:error, :not_found}
      end

      SourceRegistryVerifierWorker.run(probe_fn: probe)

      updated1 = Repo.get!(SourceRegistryEntry, stale1.id)
      updated2 = Repo.get!(SourceRegistryEntry, stale2.id)

      assert updated1.consecutive_failures == 0
      assert updated2.consecutive_failures == 3
      assert updated2.is_enabled == false
    end

    test "returns :ok regardless of outcomes" do
      stale_entry()
      assert :ok = SourceRegistryVerifierWorker.run(probe_fn: fail_probe())
    end
  end

  describe "perform/1" do
    test "delegates to run/1 and returns :ok" do
      # perform/1 calls run/1 with the real probe_url — just verify it completes without crash
      # when there are no stale entries.
      assert :ok = SourceRegistryVerifierWorker.perform(%Oban.Job{args: %{}, id: 1})
    end
  end
end
