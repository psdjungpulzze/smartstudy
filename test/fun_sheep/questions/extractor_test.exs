defmodule FunSheep.Questions.ExtractorTest do
  use ExUnit.Case, async: true

  import Mox

  alias FunSheep.Interactor.AgentsMock
  alias FunSheep.Questions.Extractor

  setup :verify_on_exit!

  setup do
    Application.put_env(:fun_sheep, :interactor_agents_impl, AgentsMock)
    on_exit(fn -> Application.delete_env(:fun_sheep, :interactor_agents_impl) end)
    :ok
  end

  @question_bank_text """
  Practice Set — Chapter 10: Meiosis

  1. Which phase of meiosis is characterized by pairing of homologous chromosomes?
     (A) Prophase I
     (B) Metaphase II
     (C) Anaphase I
     (D) Telophase II

  2. Nondisjunction during meiosis produces:
     (A) identical daughter cells
     (B) aneuploidy
     (C) polyploidy only
     (D) no genetic variation
  """

  describe "extract/2 — AI path success" do
    test "returns normalized questions that clear all pre-insert gates" do
      response =
        Jason.encode!([
          %{
            "content" =>
              "Which phase of meiosis is characterized by pairing of homologous chromosomes?",
            "answer" => "A",
            "question_type" => "multiple_choice",
            "options" => %{
              "A" => "Prophase I",
              "B" => "Metaphase II",
              "C" => "Anaphase I",
              "D" => "Telophase II"
            },
            "difficulty" => "medium",
            "explanation" =>
              "Homologous chromosomes pair during prophase I, forming tetrads before crossing over."
          }
        ])

      AgentsMock
      |> expect(:chat, fn "question_extract", _prompt, _meta -> {:ok, response} end)

      [q] = Extractor.extract(@question_bank_text, source: :material)

      assert q.question_type == :multiple_choice
      assert q.difficulty == :medium
      assert map_size(q.options) >= 3
      assert q.explanation =~ "Homologous"
      assert q.source_type == :user_uploaded
      assert q.metadata["source"] == "ocr_extraction"
    end
  end

  describe "extract/2 — pre-insert gates" do
    test "rejects MCQ with fewer than 3 options" do
      response =
        Jason.encode!([
          %{
            "content" => "What is mitosis?",
            "answer" => "A",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "Cell division", "B" => "Cell death"},
            "difficulty" => "easy",
            "explanation" => "Mitosis is cell division."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "rejects content shorter than 20 chars" do
      response =
        Jason.encode!([
          %{
            "content" => "What is it?",
            "answer" => "B",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "x", "B" => "y", "C" => "z", "D" => "w"},
            "difficulty" => "easy",
            "explanation" => "A concept."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "rejects answer-key artifact patterns" do
      response =
        Jason.encode!([
          %{
            "content" => "C 2. C 3. C 4. B 5. A 6. D",
            "answer" => "C",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "x", "B" => "y", "C" => "z", "D" => "w"},
            "difficulty" => "easy",
            "explanation" => "Answer key entries."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "rejects short stems that end mid-word (truncation signal)" do
      response =
        Jason.encode!([
          %{
            "content" => "Charged dye molecules could equilibra",
            "answer" => "False",
            "question_type" => "true_false",
            "difficulty" => "medium",
            "explanation" => "Incomplete question."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "rejects non-free-response question with empty answer" do
      response =
        Jason.encode!([
          %{
            "content" => "Which structure produces ribosomes in the cell?",
            "answer" => "",
            "question_type" => "short_answer",
            "difficulty" => "medium",
            "explanation" => "The nucleolus."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "accepts free-response with empty answer (ungradable without a human)" do
      response =
        Jason.encode!([
          %{
            "content" =>
              "Describe how the electron transport chain would halt if oxygen became unavailable.",
            "answer" => "",
            "question_type" => "free_response",
            "difficulty" => "hard",
            "explanation" => "Free-response probe; graded with a rubric."
          }
        ])

      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, response} end)

      assert [%{question_type: :free_response}] =
               Extractor.extract(@question_bank_text, source: :material)
    end
  end

  describe "extract/2 — short-circuits and errors" do
    test "returns [] on text below the length floor without calling the agent" do
      assert [] = Extractor.extract("too short", source: :material)
    end

    test "returns [] on unparseable agent response" do
      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:ok, "not json"} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "returns [] on agent transport error" do
      AgentsMock
      |> expect(:chat, fn _, _, _ -> {:error, :connection_refused} end)

      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end
  end

  describe "accept_legacy?/1" do
    test "same gate applies to regex-extracted shapes" do
      good = %{
        content: "Which structure packages proteins in the cell?",
        answer: "B",
        question_type: :multiple_choice,
        options: %{"A" => "Nucleus", "B" => "Golgi", "C" => "Ribosome", "D" => "Lysosome"}
      }

      bad = %{
        content: "C 2. C 3. C 4.",
        answer: "C",
        question_type: :multiple_choice,
        options: %{"A" => "x", "B" => "y", "C" => "z", "D" => "w"}
      }

      assert Extractor.accept_legacy?(good)
      refute Extractor.accept_legacy?(bad)
    end
  end
end
