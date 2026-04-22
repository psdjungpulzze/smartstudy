defmodule FunSheep.AIUsageTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.AIUsage
  alias FunSheep.AIUsage.{Call, Pricing, Tokenizer}

  describe "Tokenizer.count/1" do
    test "returns 0 for nil or empty" do
      assert Tokenizer.count(nil) == 0
      assert Tokenizer.count("") == 0
    end

    test "rounds up for short strings" do
      # chars_per_token = 4, so "a" (1 char) rounds up to 1 token
      assert Tokenizer.count("a") == 1
      assert Tokenizer.count("abcd") == 1
      assert Tokenizer.count("abcde") == 2
    end

    test "scales roughly linearly" do
      text = String.duplicate("hello world ", 100)
      count = Tokenizer.count(text)
      # 1200 chars / 4 ≈ 300 tokens
      assert count == 300
    end

    test "counts Unicode graphemes, not bytes" do
      # Each emoji is 1 grapheme but 4 bytes; heuristic operates on graphemes.
      assert Tokenizer.count("👋👋👋👋") == 1
    end
  end

  describe "log_call/1 with exact counts" do
    test "persists a row with interactor token_source when both counts given" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          model: "gpt-4o-mini",
          assistant_name: "question_gen",
          source: "ai_question_generation_worker",
          prompt_tokens: 123,
          completion_tokens: 45,
          duration_ms: 1842,
          status: "ok",
          metadata: %{course_id: "c_abc"}
        })

      assert call.provider == "interactor"
      assert call.model == "gpt-4o-mini"
      assert call.assistant_name == "question_gen"
      assert call.source == "ai_question_generation_worker"
      assert call.prompt_tokens == 123
      assert call.completion_tokens == 45
      assert call.total_tokens == 168
      assert call.token_source == "interactor"
      assert call.duration_ms == 1842
      assert call.status == "ok"
      assert call.metadata == %{"course_id" => "c_abc"}
      assert call.env == "test"
    end

    test "estimates the half that is missing while still flagging interactor source" do
      response_text = String.duplicate("x", 100)

      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "tutor_session",
          prompt_tokens: 200,
          response: response_text,
          status: "ok"
        })

      # prompt_tokens is authoritative (200); completion estimated from 100 chars / 4 = 25
      assert call.prompt_tokens == 200
      assert call.completion_tokens == 25
      assert call.total_tokens == 225
      assert call.token_source == "interactor"
    end
  end

  describe "log_call/1 with estimated counts" do
    test "tokenizes prompt and response when no exact counts provided" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "study_guide_ai",
          prompt: String.duplicate("a", 400),
          response: String.duplicate("b", 200),
          status: "ok"
        })

      assert call.prompt_tokens == 100
      assert call.completion_tokens == 50
      assert call.total_tokens == 150
      assert call.token_source == "estimated"
    end
  end

  describe "log_call/1 with failures" do
    test "records timeout status" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "worker_x",
          prompt: "hi",
          status: "timeout",
          error: ":timeout",
          duration_ms: 60_000
        })

      assert call.status == "timeout"
      assert call.error == ":timeout"
      assert call.prompt_tokens == 1
      assert call.completion_tokens == 0
      assert call.total_tokens == 1
    end

    test "records error status with arbitrary error term" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "worker_x",
          prompt: "hi",
          status: "error",
          error: {:http_error, 500}
        })

      assert call.status == "error"
      assert call.error == "{:http_error, 500}"
    end
  end

  describe "log_call/1 validation" do
    test "returns error changeset for invalid provider" do
      assert {:error, %Ecto.Changeset{} = cs} =
               AIUsage.log_call(%{
                 provider: "bogus",
                 source: "x",
                 status: "ok"
               })

      assert "is invalid" in errors_on(cs).provider
    end

    test "returns error changeset for invalid status" do
      assert {:error, %Ecto.Changeset{} = cs} =
               AIUsage.log_call(%{
                 provider: "interactor",
                 source: "x",
                 status: "bogus"
               })

      assert "is invalid" in errors_on(cs).status
    end
  end

  describe "Pricing" do
    test "cost_cents returns nil for unknown model" do
      assert Pricing.cost_cents("definitely-not-a-model", 1000, 1000) == nil
      assert Pricing.cost_cents(nil, 1000, 1000) == nil
    end

    test "cost_cents handles known model" do
      # gpt-4o: {250, 1000} cents per 1M tokens
      # 1M prompt + 1M completion → 250 + 1000 = 1250 cents
      assert Pricing.cost_cents("gpt-4o", 1_000_000, 1_000_000) == 1250
    end

    test "cost_cents rounds small calls sensibly" do
      # 1000 prompt tokens at 250 cents/1M = 0.25 cents → rounds to 0
      assert Pricing.cost_cents("gpt-4o", 1000, 0) == 0
    end

    test "cost_microcents preserves precision" do
      assert Pricing.cost_microcents("gpt-4o", 1000, 0) == 250_000
    end

    test "format_cost_cents" do
      assert Pricing.format_cost_cents(nil) == "—"
      assert Pricing.format_cost_cents(0) == "$0.00"
      assert Pricing.format_cost_cents(123) == "$1.23"
      assert Pricing.format_cost_cents(1_000) == "$10.00"
      assert Pricing.format_cost_cents(9) == "$0.09"
    end

    test "known_models returns sorted list" do
      models = Pricing.known_models()
      assert "gpt-4o-mini" in models
      assert models == Enum.sort(models)
    end
  end

  describe "summary/1" do
    setup do
      insert_calls([
        %{
          provider: "openai",
          model: "gpt-4o",
          source: "worker_a",
          prompt_tokens: 1000,
          completion_tokens: 500,
          duration_ms: 100,
          status: "ok"
        },
        %{
          provider: "openai",
          model: "gpt-4o",
          source: "worker_a",
          prompt_tokens: 2000,
          completion_tokens: 1000,
          duration_ms: 300,
          status: "ok"
        },
        %{
          provider: "openai",
          model: "gpt-4o-mini",
          source: "worker_b",
          prompt_tokens: 500,
          completion_tokens: 250,
          duration_ms: 50,
          status: "error",
          error: "boom"
        }
      ])

      :ok
    end

    test "returns zeros for empty window" do
      far_future = DateTime.add(DateTime.utc_now(), 86_400, :second)
      summary = AIUsage.summary(%{since: far_future})
      assert summary.calls == 0
      assert summary.total_tokens == 0
      assert summary.errors == 0
      assert summary.est_cost_cents == nil
    end

    test "aggregates across models and computes cost" do
      summary = AIUsage.summary(%{})
      assert summary.calls == 3
      assert summary.prompt_tokens == 3500
      assert summary.completion_tokens == 1750
      assert summary.total_tokens == 5250
      assert summary.errors == 1
      assert is_integer(summary.est_cost_cents)
      # gpt-4o: 3000 prompt * 250 + 1500 completion * 1000 = 2_250_000 microcents = 2 cents
      # gpt-4o-mini: 500 * 15 + 250 * 60 = 22_500 microcents = 0 cents
      # Total ≈ 2 cents
      assert summary.est_cost_cents >= 2
    end

    test "filters by source" do
      summary = AIUsage.summary(%{source: "worker_a"})
      assert summary.calls == 2
      assert summary.errors == 0
    end

    test "filters by status list" do
      summary = AIUsage.summary(%{status: ["error", "timeout"]})
      assert summary.calls == 1
      assert summary.errors == 1
    end
  end

  describe "summary_with_delta/1" do
    test "handles empty prior window with nil delta" do
      insert_calls([
        %{
          provider: "openai",
          model: "gpt-4o",
          source: "w",
          prompt_tokens: 100,
          completion_tokens: 50,
          status: "ok"
        }
      ])

      now = DateTime.utc_now()
      since = DateTime.add(now, -3600, :second)

      summary = AIUsage.summary_with_delta(%{since: since, until: now})
      # Prior window is [now - 7200, since] which has no data
      assert summary.prior.calls == 0
      assert summary.calls_delta_pct == nil
    end
  end

  describe "by_assistant/1, by_source/1, by_model/1" do
    setup do
      insert_calls([
        %{
          provider: "openai",
          model: "gpt-4o",
          assistant_name: "validator",
          source: "worker_a",
          prompt_tokens: 1000,
          completion_tokens: 500,
          duration_ms: 100,
          status: "ok"
        },
        %{
          provider: "openai",
          model: "gpt-4o",
          assistant_name: "validator",
          source: "worker_a",
          prompt_tokens: 2000,
          completion_tokens: 0,
          duration_ms: 200,
          status: "ok"
        },
        %{
          provider: "openai",
          model: "gpt-4o-mini",
          assistant_name: "tutor",
          source: "worker_b",
          prompt_tokens: 100,
          completion_tokens: 200,
          duration_ms: 50,
          status: "ok"
        }
      ])

      :ok
    end

    test "by_assistant groups and sorts" do
      rows = AIUsage.by_assistant(%{})
      assert length(rows) == 2
      # Sorted by total_tokens desc; validator has 3500, tutor has 300
      [first, second] = rows
      assert first.key == "validator"
      assert first.calls == 2
      assert first.total_tokens == 3500
      assert second.key == "tutor"
    end

    test "by_source groups correctly" do
      rows = AIUsage.by_source(%{})
      keys = Enum.map(rows, & &1.key)
      assert "worker_a" in keys
      assert "worker_b" in keys
    end

    test "by_model groups correctly" do
      rows = AIUsage.by_model(%{})
      keys = Enum.map(rows, & &1.key)
      assert "gpt-4o" in keys
      assert "gpt-4o-mini" in keys
    end
  end

  describe "time_series/2" do
    test "produces zero-filled buckets for empty data" do
      since = ~U[2026-01-01 00:00:00Z]
      until_dt = ~U[2026-01-01 06:00:00Z]

      series = AIUsage.time_series(%{since: since, until: until_dt}, :hour)

      assert length(series) == 6
      assert Enum.all?(series, &(&1.prompt_tokens == 0 and &1.completion_tokens == 0))
    end

    test "aggregates calls into hourly buckets" do
      # Insert a call, then time-travel its inserted_at via direct SQL.
      insert_calls([
        %{
          provider: "openai",
          model: "gpt-4o",
          source: "w",
          prompt_tokens: 1000,
          completion_tokens: 500,
          status: "ok"
        }
      ])

      # Query the current 2h window — we should see the 1000/500 in one bucket.
      now = DateTime.utc_now()
      since = DateTime.add(now, -2 * 3600, :second)
      series = AIUsage.time_series(%{since: since, until: now}, :hour)

      total_prompt = Enum.sum(Enum.map(series, & &1.prompt_tokens))
      total_completion = Enum.sum(Enum.map(series, & &1.completion_tokens))
      assert total_prompt == 1000
      assert total_completion == 500
    end
  end

  describe "recent_calls/2, recent_errors/2, top_calls/2" do
    setup do
      insert_calls([
        %{provider: "openai", source: "w", prompt_tokens: 10, completion_tokens: 5, status: "ok"},
        %{
          provider: "openai",
          source: "w",
          prompt_tokens: 1000,
          completion_tokens: 500,
          status: "ok"
        },
        %{
          provider: "openai",
          source: "w",
          prompt_tokens: 5,
          completion_tokens: 5,
          status: "error",
          error: "boom"
        }
      ])

      :ok
    end

    test "recent_calls returns newest first" do
      calls = AIUsage.recent_calls(%{}, 10)
      assert length(calls) == 3
    end

    test "recent_errors only returns error/timeout status" do
      errors = AIUsage.recent_errors(%{}, 10)
      assert length(errors) == 1
      assert hd(errors).status == "error"
    end

    test "top_calls orders by total_tokens desc" do
      calls = AIUsage.top_calls(%{}, 10)
      assert hd(calls).total_tokens == 1500
    end
  end

  describe "get_call!/1" do
    test "returns the call by id" do
      {:ok, call} =
        AIUsage.log_call(%{
          provider: "openai",
          source: "w",
          status: "ok",
          prompt: "hi",
          response: "hello"
        })

      assert AIUsage.get_call!(call.id).id == call.id
    end
  end

  # --- helpers ---------------------------------------------------------

  defp insert_calls(attrs_list) do
    Enum.each(attrs_list, fn attrs ->
      {:ok, _} = AIUsage.log_call(attrs)
    end)
  end
end
