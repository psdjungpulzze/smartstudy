defmodule FunSheep.Questions.DeduplicatorTest do
  use ExUnit.Case, async: true

  alias FunSheep.Questions.Deduplicator

  describe "fingerprint/1" do
    test "returns a 16-character hex string" do
      fp = Deduplicator.fingerprint("What is 2 + 2?")
      assert is_binary(fp)
      assert String.length(fp) == 16
      assert fp =~ ~r/^[0-9a-f]{16}$/
    end

    test "is deterministic — same content always produces same fingerprint" do
      content = "Which of the following is a prime number?"
      assert Deduplicator.fingerprint(content) == Deduplicator.fingerprint(content)
    end

    test "normalizes case — uppercase and lowercase match" do
      assert Deduplicator.fingerprint("What is photosynthesis?") ==
               Deduplicator.fingerprint("WHAT IS PHOTOSYNTHESIS?")
    end

    test "normalizes punctuation — punctuation differences don't affect fingerprint" do
      assert Deduplicator.fingerprint("What is photosynthesis?") ==
               Deduplicator.fingerprint("What is photosynthesis")
    end

    test "normalizes whitespace — extra spaces don't affect fingerprint" do
      assert Deduplicator.fingerprint("What  is   photosynthesis?") ==
               Deduplicator.fingerprint("What is photosynthesis?")
    end

    test "different content produces different fingerprints" do
      fp1 = Deduplicator.fingerprint("What is photosynthesis?")
      fp2 = Deduplicator.fingerprint("What is cellular respiration?")
      assert fp1 != fp2
    end

    test "returns nil for non-binary input" do
      assert Deduplicator.fingerprint(nil) == nil
      assert Deduplicator.fingerprint(42) == nil
    end

    test "handles empty string" do
      fp = Deduplicator.fingerprint("")
      assert is_binary(fp)
      assert String.length(fp) == 16
    end
  end
end
