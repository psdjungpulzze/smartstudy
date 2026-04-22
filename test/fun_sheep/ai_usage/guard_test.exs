defmodule FunSheep.AIUsage.GuardTest do
  # Not async — this module mutates :persistent_term-backed ETS + global
  # application env that other tests also depend on.
  use FunSheep.DataCase, async: false

  alias FunSheep.AIUsage
  alias FunSheep.AIUsage.Guard

  setup do
    Guard.reset_all()

    # Capture & restore Guard config so tests that tweak thresholds don't
    # leak to sibling tests.
    original = Application.get_env(:fun_sheep, Guard, [])
    on_exit(fn -> Application.put_env(:fun_sheep, Guard, original) end)

    :ok
  end

  describe "circuit breaker" do
    test "check/1 returns :ok with no prior failures" do
      assert :ok = Guard.check("fresh_source")
    end

    test "stays closed under the threshold" do
      Application.put_env(:fun_sheep, Guard,
        circuit_threshold: 5,
        circuit_window_ms: 60_000,
        circuit_cooldown_ms: 120_000
      )

      for _ <- 1..4, do: Guard.record_failure("validator", :parse_failed)
      assert :ok = Guard.check("validator")
    end

    test "opens after `circuit_threshold` failures inside the window" do
      Application.put_env(:fun_sheep, Guard,
        circuit_threshold: 3,
        circuit_window_ms: 60_000,
        circuit_cooldown_ms: 120_000
      )

      for _ <- 1..3, do: Guard.record_failure("validator", :parse_failed)

      assert {:error, :circuit_open} = Guard.check("validator")
    end

    test "success resets the counter" do
      Application.put_env(:fun_sheep, Guard,
        circuit_threshold: 3,
        circuit_window_ms: 60_000,
        circuit_cooldown_ms: 120_000
      )

      Guard.record_failure("validator", :parse_failed)
      Guard.record_failure("validator", :parse_failed)
      Guard.record_success("validator")
      # Two more failures should not trip because success reset the window.
      Guard.record_failure("validator", :parse_failed)
      Guard.record_failure("validator", :parse_failed)

      assert :ok = Guard.check("validator")
    end

    test "failures are scoped per-source — one source tripping doesn't affect another" do
      Application.put_env(:fun_sheep, Guard,
        circuit_threshold: 2,
        circuit_window_ms: 60_000,
        circuit_cooldown_ms: 120_000
      )

      Guard.record_failure("validator", :parse_failed)
      Guard.record_failure("validator", :parse_failed)

      assert {:error, :circuit_open} = Guard.check("validator")
      assert :ok = Guard.check("classifier")
    end
  end

  describe "daily token budget" do
    test "allows calls when source has no budget cap configured" do
      Application.put_env(:fun_sheep, Guard, daily_budget_tokens: %{})

      assert :ok = Guard.check("unbudgeted_source")
    end

    test "blocks calls when the day's recorded usage exceeds the cap" do
      Application.put_env(:fun_sheep, Guard, daily_budget_tokens: %{"cheap_source" => 100})

      # Log a single big call so `AIUsage.summary(source: "cheap_source")`
      # reports total_tokens >= 100.
      {:ok, _} =
        AIUsage.log_call(%{
          provider: "openai",
          source: "cheap_source",
          assistant_name: "cheap_source",
          prompt_tokens: 80,
          completion_tokens: 50,
          status: "ok"
        })

      assert {:error, :budget_exceeded} = Guard.check("cheap_source")
    end

    test "allows calls when usage is under the cap" do
      Application.put_env(:fun_sheep, Guard, daily_budget_tokens: %{"light_source" => 10_000})

      {:ok, _} =
        AIUsage.log_call(%{
          provider: "openai",
          source: "light_source",
          assistant_name: "light_source",
          prompt_tokens: 100,
          completion_tokens: 200,
          status: "ok"
        })

      assert :ok = Guard.check("light_source")
    end
  end

  describe "reset_all/0" do
    test "clears both circuit and budget state" do
      Application.put_env(:fun_sheep, Guard, circuit_threshold: 1)
      Guard.record_failure("s1", :x)
      assert {:error, :circuit_open} = Guard.check("s1")

      Guard.reset_all()
      assert :ok = Guard.check("s1")
    end
  end
end
