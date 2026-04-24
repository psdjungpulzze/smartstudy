defmodule FunSheep.MemorySpan.CalculatorTest do
  @moduledoc """
  Tests for the pure memory span calculator.

  These tests are all async (no DB) since Calculator has no side effects.
  """

  use ExUnit.Case, async: true

  alias FunSheep.MemorySpan.Calculator

  # Helper to build an attempt map
  defp attempt(is_correct, days_ago) do
    dt = DateTime.add(~U[2026-01-01 00:00:00Z], -days_ago * 86_400, :second)
    %{is_correct: is_correct, inserted_at: dt}
  end

  defp attempt_at(is_correct, datetime) do
    %{is_correct: is_correct, inserted_at: datetime}
  end

  describe "compute_question_span/1" do
    test "basic right→wrong decay is detected" do
      # Correct on day 0, wrong on day 10 → gap is 10 days = 240 hours
      attempts = [attempt(true, 20), attempt(false, 10)]
      assert {:ok, 240} = Calculator.compute_question_span(attempts)
    end

    test "multiple decay events → median returned" do
      # Correct→wrong pairs with gaps: 5d(120h), 10d(240h), 15d(360h)
      # median of [120, 240, 360] = 240
      attempts = [
        attempt(true, 45),
        attempt(false, 40),
        attempt(true, 30),
        attempt(false, 20),
        attempt(true, 15),
        attempt(false, 0)
      ]

      assert {:ok, 240} = Calculator.compute_question_span(attempts)
    end

    test "no decay events (all correct) → insufficient_data" do
      attempts = [attempt(true, 10), attempt(true, 5), attempt(true, 0)]
      assert {:insufficient_data, :no_decay_events} = Calculator.compute_question_span(attempts)
    end

    test "only wrong answers → insufficient_data" do
      attempts = [attempt(false, 10), attempt(false, 5), attempt(false, 0)]
      assert {:insufficient_data, :no_decay_events} = Calculator.compute_question_span(attempts)
    end

    test "wrong before any correct → insufficient_data" do
      attempts = [attempt(false, 5), attempt(true, 3), attempt(false, 1)]
      # first wrong has no prior correct → no decay event from it
      # correct on day 3, wrong on day 1 → gap = 2 days = 48 hours
      assert {:ok, 48} = Calculator.compute_question_span(attempts)
    end

    test "single attempt → insufficient_data" do
      assert {:insufficient_data, :no_decay_events} =
               Calculator.compute_question_span([attempt(true, 0)])

      assert {:insufficient_data, :no_decay_events} =
               Calculator.compute_question_span([attempt(false, 0)])
    end

    test "empty list → insufficient_data" do
      assert {:insufficient_data, :no_decay_events} = Calculator.compute_question_span([])
    end

    test "summer gap (> 90 days) is capped at 90 days = 2160 hours" do
      # 120-day gap gets capped to 90 days
      attempts = [attempt(true, 130), attempt(false, 10)]
      assert {:ok, 2160} = Calculator.compute_question_span(attempts)
    end

    test "exactly 90-day gap is not capped (equals limit)" do
      attempts = [attempt(true, 91), attempt(false, 1)]
      # 90 days = 2160 hours — equals max, should not be capped
      assert {:ok, 2160} = Calculator.compute_question_span(attempts)
    end

    test "gap less than 1 hour is excluded" do
      # same timestamp → gap = 0 → not counted
      t = ~U[2026-01-01 12:00:00Z]
      attempts = [attempt_at(true, t), attempt_at(false, t)]
      assert {:insufficient_data, :no_decay_events} = Calculator.compute_question_span(attempts)
    end

    test "correct then wrong then correct then wrong returns median of two gaps" do
      # correct day 30, wrong day 20 → 10d = 240h
      # correct day 10, wrong day 5 → 5d = 120h
      # median([240, 120]) = 180
      attempts = [
        attempt(true, 30),
        attempt(false, 20),
        attempt(true, 10),
        attempt(false, 5)
      ]

      assert {:ok, 180} = Calculator.compute_question_span(attempts)
    end

    test "attempts are sorted by inserted_at before processing" do
      # Provide out-of-order attempts: correct at day 20, wrong at day 10
      a1 = attempt(false, 10)
      a2 = attempt(true, 20)
      # Even if passed wrong-order, should work
      assert {:ok, 240} = Calculator.compute_question_span([a1, a2])
    end
  end

  describe "compute_topic_span/1" do
    test "aggregates question spans correctly" do
      assert {:ok, 120} = Calculator.compute_topic_span([48, 120, 240])
    end

    test "empty list → insufficient_data" do
      assert {:insufficient_data, :no_question_spans} = Calculator.compute_topic_span([])
    end

    test "all nil → insufficient_data" do
      assert {:insufficient_data, :no_question_spans} =
               Calculator.compute_topic_span([nil, nil, nil])
    end

    test "filters nils and computes median of remaining" do
      # [nil, 48, nil, 240] → median([48, 240]) = 144
      assert {:ok, 144} = Calculator.compute_topic_span([nil, 48, nil, 240])
    end

    test "single span value" do
      assert {:ok, 72} = Calculator.compute_topic_span([72])
    end
  end

  describe "median/1" do
    test "odd count — picks middle element" do
      assert 3 == Calculator.median([1, 2, 3, 4, 5])
    end

    test "even count — averages two middle elements" do
      # [2, 4, 6, 8] → (4+6)/2 = 5
      assert 5 == Calculator.median([2, 4, 6, 8])
    end

    test "single element" do
      assert 42 == Calculator.median([42])
    end

    test "unsorted input is sorted before computing" do
      # [5, 1, 3] sorted = [1, 3, 5] → median = 3
      assert 3 == Calculator.median([5, 1, 3])
    end

    test "empty list raises ArgumentError" do
      assert_raise ArgumentError, fn -> Calculator.median([]) end
    end

    test "even length with exact average" do
      # [10, 20] → (10+20)/2 = 15
      assert 15 == Calculator.median([10, 20])
    end
  end
end
