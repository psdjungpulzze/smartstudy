defmodule FunSheepWeb.StudentLive.Shared.WellbeingFramingTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheepWeb.StudentLive.Shared.WellbeingFraming

  describe "dampen_competitive?/1" do
    test "damps under-pressure and disengaged" do
      assert WellbeingFraming.dampen_competitive?(:under_pressure)
      assert WellbeingFraming.dampen_competitive?(:disengaged)
    end

    test "does not dampen thriving or steady" do
      refute WellbeingFraming.dampen_competitive?(:thriving)
      refute WellbeingFraming.dampen_competitive?(:steady)
      refute WellbeingFraming.dampen_competitive?(:insufficient_data)
    end
  end

  describe "framing_banner/1" do
    test "under_pressure surfaces supportive copy, not numbers" do
      html = render_component(&WellbeingFraming.framing_banner/1, signal: :under_pressure)
      assert html =~ "often a sign of fatigue"
      refute html =~ "percentile"
    end

    test "disengaged suggests a short restart session" do
      html = render_component(&WellbeingFraming.framing_banner/1, signal: :disengaged)
      assert html =~ "Short 15-minute sessions"
    end

    test "thriving celebrates effort" do
      html = render_component(&WellbeingFraming.framing_banner/1, signal: :thriving)
      assert html =~ "Consistent sessions"
    end

    test "steady / insufficient render nothing visible" do
      html = render_component(&WellbeingFraming.framing_banner/1, signal: :steady)
      refute html =~ "aside"
      html = render_component(&WellbeingFraming.framing_banner/1, signal: :insufficient_data)
      refute html =~ "aside"
    end
  end
end
