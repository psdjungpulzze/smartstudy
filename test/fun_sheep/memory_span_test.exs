defmodule FunSheep.MemorySpanTest do
  @moduledoc """
  Tests for the MemorySpan context presentation helpers.

  These tests are all pure (no DB) since they test span_label, span_color,
  and format_span which have no side effects.
  """

  use ExUnit.Case, async: true

  alias FunSheep.MemorySpan

  describe "span_label/1" do
    test "nil → no_data tier" do
      {tier, _desc} = MemorySpan.span_label(nil)
      assert tier == :no_data
    end

    test "nil → encouragement message" do
      {_, desc} = MemorySpan.span_label(nil)
      assert String.contains?(desc, "practicing")
    end

    test "< 72 hours → speed runner tier" do
      {label, _} = MemorySpan.span_label(24)
      assert String.contains?(label, "Speed runner")

      {label, _} = MemorySpan.span_label(71)
      assert String.contains?(label, "Speed runner")
    end

    test "72–167 hours → almost there tier" do
      {label, _} = MemorySpan.span_label(72)
      assert String.contains?(label, "Almost there")

      {label, _} = MemorySpan.span_label(167)
      assert String.contains?(label, "Almost there")
    end

    test "168–335 hours (1–2 weeks) → solid retention tier" do
      {label, _} = MemorySpan.span_label(168)
      assert String.contains?(label, "Solid retention")

      {label, _} = MemorySpan.span_label(335)
      assert String.contains?(label, "Solid retention")
    end

    test "336–671 hours (2–4 weeks) → strong memory tier" do
      {label, _} = MemorySpan.span_label(336)
      assert String.contains?(label, "Strong memory")

      {label, _} = MemorySpan.span_label(671)
      assert String.contains?(label, "Strong memory")
    end

    test ">= 672 hours (4+ weeks) → elite tier" do
      {label, _} = MemorySpan.span_label(672)
      assert String.contains?(label, "Elite")

      {label, _} = MemorySpan.span_label(10_000)
      assert String.contains?(label, "Elite")
    end

    test "each tier has a non-empty description" do
      for hours <- [nil, 24, 100, 200, 500, 1000] do
        {_, desc} = MemorySpan.span_label(hours)
        assert is_binary(desc) and byte_size(desc) > 0
      end
    end
  end

  describe "span_color/1" do
    test "nil → gray" do
      assert "gray" == MemorySpan.span_color(nil)
    end

    test "< 7 days (168h) → red" do
      assert "red" == MemorySpan.span_color(24)
      assert "red" == MemorySpan.span_color(100)
      assert "red" == MemorySpan.span_color(167)
    end

    test "7–20 days (168–503h) → yellow" do
      assert "yellow" == MemorySpan.span_color(168)
      assert "yellow" == MemorySpan.span_color(300)
      assert "yellow" == MemorySpan.span_color(503)
    end

    test ">= 21 days (504h) → green" do
      assert "green" == MemorySpan.span_color(504)
      assert "green" == MemorySpan.span_color(1000)
      assert "green" == MemorySpan.span_color(10_000)
    end

    test "boundary: exactly 7 days = 168h → yellow (not red)" do
      assert "yellow" == MemorySpan.span_color(7 * 24)
    end

    test "boundary: exactly 21 days = 504h → green (not yellow)" do
      assert "green" == MemorySpan.span_color(21 * 24)
    end
  end

  describe "format_span/1" do
    test "nil → em dash" do
      assert "—" == MemorySpan.format_span(nil)
    end

    test "< 1 day" do
      assert "< 1 day" == MemorySpan.format_span(12)
    end

    test "1 day singular" do
      assert "~1 day" == MemorySpan.format_span(24)
    end

    test "2–6 days plural" do
      assert "~3 days" == MemorySpan.format_span(72)
      assert "~5 days" == MemorySpan.format_span(5 * 24)
    end

    test "7–13 days → ~1 week" do
      assert "~1 week" == MemorySpan.format_span(7 * 24)
      assert "~1 week" == MemorySpan.format_span(13 * 24)
    end

    test "14–20 days → ~2 weeks" do
      assert "~2 weeks" == MemorySpan.format_span(14 * 24)
      assert "~2 weeks" == MemorySpan.format_span(20 * 24)
    end

    test "21–34 days → ~N weeks" do
      assert "~3 weeks" == MemorySpan.format_span(21 * 24)
      assert "~4 weeks" == MemorySpan.format_span(28 * 24)
    end

    test "35–59 days → ~1 month" do
      assert "~1 month" == MemorySpan.format_span(35 * 24)
      assert "~1 month" == MemorySpan.format_span(59 * 24)
    end

    test ">= 60 days → ~N months" do
      assert "~2 months" == MemorySpan.format_span(60 * 24)
      assert "~3 months" == MemorySpan.format_span(90 * 24)
    end
  end
end
