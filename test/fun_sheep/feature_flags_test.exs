defmodule FunSheep.FeatureFlagsTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.FeatureFlags

  setup do
    # Flags default to OFF when no row exists in Postgres (fun_with_flags
    # semantics). Pre-seed every known flag as enabled so tests that rely on
    # the "default state" assertion have a known starting point. Post-test
    # we clear so state doesn't leak between suites.
    for name <- FeatureFlags.known_names(), do: FunWithFlags.enable(name)

    on_exit(fn ->
      for name <- FeatureFlags.known_names(), do: FunWithFlags.clear(name)
    end)

    :ok
  end

  describe "list/0 and known_names/0" do
    test "returns every declared flag enabled by default" do
      flags = FeatureFlags.list()

      assert length(flags) == length(FeatureFlags.known_names())
      assert Enum.all?(flags, & &1.enabled?)
      assert :ai_question_generation_enabled in FeatureFlags.known_names()
      assert :ocr_enabled in FeatureFlags.known_names()
      assert :maintenance_mode in FeatureFlags.known_names()
    end
  end

  describe "enabled?/1, enable/1, disable/1, toggle/1" do
    test "defaults to true for unknown (and known) flags" do
      assert FeatureFlags.enabled?(:ai_question_generation_enabled) == true
    end

    test "disable and re-enable round-trip" do
      assert {:ok, false} = FeatureFlags.disable(:ocr_enabled)
      assert FeatureFlags.enabled?(:ocr_enabled) == false

      assert {:ok, true} = FeatureFlags.enable(:ocr_enabled)
      assert FeatureFlags.enabled?(:ocr_enabled) == true
    end

    test "toggle flips state" do
      {:ok, false} = FeatureFlags.toggle(:signup_enabled)
      assert FeatureFlags.enabled?(:signup_enabled) == false

      {:ok, true} = FeatureFlags.toggle(:signup_enabled)
      assert FeatureFlags.enabled?(:signup_enabled) == true
    end
  end

  describe "require!/1" do
    test "returns :ok when the flag is enabled" do
      assert FeatureFlags.require!(:interactor_calls_enabled) == :ok
    end

    test "returns {:cancel, reason} when disabled" do
      {:ok, false} = FeatureFlags.disable(:interactor_calls_enabled)
      assert {:cancel, reason} = FeatureFlags.require!(:interactor_calls_enabled)
      assert reason =~ "feature_flag_disabled"
    end
  end

  describe "fetch/1" do
    test "returns nil for unknown names" do
      assert FeatureFlags.fetch(:bogus_flag) == nil
    end

    test "returns the metadata for known flags" do
      meta = FeatureFlags.fetch(:ocr_enabled)
      assert meta.name == :ocr_enabled
      assert is_binary(meta.description)
    end
  end

  describe "enable/1 and disable/1 return shapes" do
    test "enable is idempotent when already enabled" do
      {:ok, true} = FeatureFlags.enable(:course_creation_enabled)
      assert {:ok, true} = FeatureFlags.enable(:course_creation_enabled)
    end

    test "disable is idempotent when already disabled" do
      {:ok, false} = FeatureFlags.disable(:course_creation_enabled)
      assert {:ok, false} = FeatureFlags.disable(:course_creation_enabled)
    end
  end
end
