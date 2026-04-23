defmodule FunSheep.Content.MaterialClassifierTest do
  use ExUnit.Case, async: true

  import Mox

  alias FunSheep.Content.MaterialClassifier
  alias FunSheep.Interactor.AgentsMock

  setup :verify_on_exit!

  setup do
    Application.put_env(:fun_sheep, :interactor_agents_impl, AgentsMock)
    on_exit(fn -> Application.delete_env(:fun_sheep, :interactor_agents_impl) end)
    :ok
  end

  # Text patterns drawn from the mid-April prod audit of course d44628ca.
  # The answer_key_sample mirrors the exact content OCR'd from
  # `Biology Answers - 31.jpg`, the material that produced 462 garbage
  # questions — the headline failure Phase 2 prevents.
  @answer_key_sample """
  ANSWER KEY — Biology Chapter 31

  1. C    2. C    3. C    4. B    5. A
  6. D    7. A    8. B    9. D   10. C
  11. B  12. A   13. C   14. D   15. B
  16. A  17. B   18. C   19. D   20. A
  """

  @textbook_sample """
  Cell membranes are semi-permeable barriers composed of a phospholipid
  bilayer with embedded proteins. The fluid mosaic model describes the
  membrane as a dynamic structure in which lipids and proteins move
  laterally within the plane of the membrane. Transport across the
  membrane can be passive (diffusion, facilitated diffusion, osmosis)
  or active (requiring ATP). Selective permeability allows the cell to
  maintain homeostasis — regulating ion concentrations, pH, and the
  flow of nutrients and waste products.
  """

  @question_bank_sample """
  Practice Set — Chapter 10: Meiosis

  1. Which phase of meiosis is characterized by the pairing of
     homologous chromosomes?
     (A) Prophase I    (B) Metaphase II
     (C) Anaphase I    (D) Telophase II

  2. Crossing over during prophase I produces:
     (A) identical daughter cells
     (B) new combinations of alleles
     (C) diploid gametes
     (D) triploid zygotes

  3. Nondisjunction in meiosis results in:
     (A) aneuploidy
     (B) polyploidy
     (C) euploidy
     (D) haploidy
  """

  describe "classify/2" do
    test "tags an answer-key page as :answer_key" do
      AgentsMock
      |> expect(:chat, fn "material_content_classifier", _prompt, _meta ->
        {:ok,
         ~s({"kind": "answer_key", "confidence": 0.95, "notes": "No question stems; letters only."})}
      end)

      assert {:ok, %{kind: :answer_key, confidence: 0.95}} =
               MaterialClassifier.classify(@answer_key_sample, subject: "AP Biology")
    end

    test "tags textbook prose as :knowledge_content" do
      AgentsMock
      |> expect(:chat, fn _, _, _ ->
        {:ok,
         ~s({"kind": "knowledge_content", "confidence": 0.92, "notes": "Expository prose, no numbered questions."})}
      end)

      assert {:ok, %{kind: :knowledge_content, confidence: 0.92}} =
               MaterialClassifier.classify(@textbook_sample)
    end

    test "tags a numbered multiple-choice set as :question_bank" do
      AgentsMock
      |> expect(:chat, fn _, _, _ ->
        {:ok,
         ~s({"kind": "question_bank", "confidence": 0.96, "notes": "Numbered stems with 4 options each."})}
      end)

      assert {:ok, %{kind: :question_bank, confidence: 0.96}} =
               MaterialClassifier.classify(@question_bank_sample)
    end

    test "downgrades low-confidence verdicts to :uncertain" do
      AgentsMock
      |> expect(:chat, fn _, _, _ ->
        {:ok, ~s({"kind": "question_bank", "confidence": 0.4, "notes": "Sparse signal."})}
      end)

      # Default floor is 0.6; 0.4 should fall through to :uncertain.
      assert {:ok, %{kind: :uncertain, confidence: 0.4}} =
               MaterialClassifier.classify(@question_bank_sample)
    end

    test "short text short-circuits to :unusable without calling the agent" do
      # No AgentsMock expectation → test fails if the classifier calls out.
      assert {:ok, %{kind: :unusable}} = MaterialClassifier.classify("blank page")
    end

    test "returns {:error, :unparseable_response} on malformed agent output" do
      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, "not json at all"} end)

      assert {:error, :unparseable_response} =
               MaterialClassifier.classify(@textbook_sample)
    end

    test "propagates transport errors from the agent" do
      AgentsMock
      |> expect(:chat, fn _, _, _ ->
        {:error, %RuntimeError{message: "connection_refused"}}
      end)

      assert {:error, %RuntimeError{}} = MaterialClassifier.classify(@textbook_sample)
    end
  end
end
