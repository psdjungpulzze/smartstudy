defmodule FunSheep.Workers.QuestionExtractionWorkerTest do
  use ExUnit.Case, async: true

  alias FunSheep.Workers.QuestionExtractionWorker

  describe "material kind exclusion invariant" do
    test ":answer_key is excluded from both the primary and fallback pools" do
      # Regression guard for the answer-key-as-source bug (CR-001 section c):
      # if either list ever admits :answer_key, uploaded answer keys will be
      # OCR'd and fed to the question extractor's regex patterns, producing
      # hundreds of bogus questions per file (one per numbered answer).
      refute :answer_key in QuestionExtractionWorker.question_kinds()
      refute :answer_key in QuestionExtractionWorker.textbook_fallback_kinds()
    end

    test "primary pool is limited to sample_questions" do
      assert QuestionExtractionWorker.question_kinds() == [:sample_questions]
    end

    test "fallback pool only contains textbook-like kinds" do
      kinds = QuestionExtractionWorker.textbook_fallback_kinds()
      # All fallback kinds must be valid material_kinds (regression guard
      # against typos introducing unreachable atoms).
      assert Enum.all?(kinds, &(&1 in FunSheep.Content.UploadedMaterial.material_kinds()))
    end
  end
end
