defmodule FunSheep.Questions.ExtractorTest do
  use ExUnit.Case, async: true

  import Mox

  alias FunSheep.AI.ClientMock
  alias FunSheep.Questions.Extractor

  setup :verify_on_exit!

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

      expect(ClientMock, :call, fn _sys, _usr, %{source: "questions_extractor"} ->
        {:ok, response}
      end)

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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
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

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      assert [%{question_type: :free_response}] =
               Extractor.extract(@question_bank_text, source: :material)
    end
  end

  describe "extract/2 — short-circuits and errors" do
    test "returns [] on text below the length floor without calling the LLM" do
      assert [] = Extractor.extract("too short", source: :material)
    end

    test "returns [] on unparseable LLM response" do
      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, "not json"} end)
      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end

    test "returns [] on LLM transport error" do
      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:error, :connection_refused} end)
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

  describe "extract/2 — content > 4000 chars gate" do
    test "rejects question whose content exceeds 4000 characters" do
      long_content = String.duplicate("A very long question stem that will be rejected. ", 90)
      assert String.length(long_content) > 4000

      response =
        Jason.encode!([
          %{
            "content" => long_content,
            "answer" => "B",
            "question_type" => "short_answer",
            "difficulty" => "easy",
            "explanation" => "This question is way too long."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)
      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end
  end

  describe "extract/2 — long text sampling path" do
    test "calls LLM even when text exceeds 12000 chars (sample truncation)" do
      # 15000 chars — forces sample/1 to truncate
      long_text = String.duplicate("This is educational content about meiosis and cell division. ", 250)
      assert String.length(long_text) > 12_000

      response =
        Jason.encode!([
          %{
            "content" => "Which phase of meiosis produces haploid daughter cells?",
            "answer" => "Telophase II",
            "question_type" => "short_answer",
            "difficulty" => "medium",
            "explanation" => "Telophase II concludes meiosis with four haploid cells."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      result = Extractor.extract(long_text, source: :material)
      assert length(result) == 1
    end
  end

  describe "extract/2 — JSON object wrapped response" do
    test "parses {\"questions\": [...]} wrapper format" do
      q = %{
        "content" => "What is the powerhouse of the cell?",
        "answer" => "Mitochondria",
        "question_type" => "short_answer",
        "difficulty" => "easy",
        "explanation" => "The mitochondria generates ATP via cellular respiration."
      }

      wrapped_response = Jason.encode!(%{"questions" => [q]})

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, wrapped_response} end)

      [extracted] = Extractor.extract(@question_bank_text, source: :material)
      assert extracted.content == "What is the powerhouse of the cell?"
    end
  end

  describe "extract/2 — fragment gate edge case" do
    test "does NOT reject content >= 100 chars even when ending in lowercase" do
      # Fragment gate only fires on content < 100 chars ending lowercase;
      # content >= 100 chars ending lowercase is a complete sentence and passes.
      long_lowercase_end =
        "Explain why the electron transport chain halts when oxygen becomes unavailable in aerobic respiration"

      assert String.length(long_lowercase_end) >= 100
      assert String.last(long_lowercase_end) =~ ~r/[a-z]/

      response =
        Jason.encode!([
          %{
            "content" => long_lowercase_end,
            "answer" => "Without O2, electrons cannot be passed to terminal acceptor, halting ATP synthesis.",
            "question_type" => "short_answer",
            "difficulty" => "hard",
            "explanation" => "O2 is the terminal electron acceptor in the ETC."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      [q] = Extractor.extract(@question_bank_text, source: :material)
      assert q.content == long_lowercase_end
    end
  end

  describe "extract/2 — source type tagging" do
    test "tags extracted question with :web_scraped source type for web source" do
      response =
        Jason.encode!([
          %{
            "content" => "Which structure packages proteins for export in eukaryotic cells?",
            "answer" => "Golgi apparatus",
            "question_type" => "short_answer",
            "difficulty" => "medium",
            "explanation" => "The Golgi apparatus processes and packages proteins."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      [q] = Extractor.extract(@question_bank_text, source: :web, source_ref: %{source_url: "https://example.com/bio"})
      assert q.source_type == :web_scraped
      assert q.metadata["source"] == "web_scrape"
      assert q.source_url == "https://example.com/bio"
    end

    test "tags extracted question with :curated source type when source is unspecified" do
      response =
        Jason.encode!([
          %{
            "content" => "What is the function of chloroplasts in plant cells?",
            "answer" => "Photosynthesis",
            "question_type" => "short_answer",
            "difficulty" => "easy",
            "explanation" => "Chloroplasts convert sunlight into chemical energy via photosynthesis."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      [q] = Extractor.extract(@question_bank_text)
      assert q.source_type == :curated
      assert q.metadata["source"] == "curated"
    end
  end

  describe "extract/2 — prompt context opts" do
    test "includes test_type and section_hint context in the LLM call without error" do
      response =
        Jason.encode!([
          %{
            "content" => "Which of the following represents the correct order of mitosis?",
            "answer" => "A",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "Prophase, Metaphase, Anaphase, Telophase", "B" => "Metaphase, Prophase, Anaphase, Telophase", "C" => "Anaphase, Metaphase, Prophase, Telophase", "D" => "Telophase, Anaphase, Metaphase, Prophase"},
            "difficulty" => "medium",
            "explanation" => "Mitosis proceeds through PMAT stages."
          }
        ])

      expect(ClientMock, :call, fn _sys, user_prompt, _opts ->
        assert user_prompt =~ "SAT"
        assert user_prompt =~ "Cell Biology"
        {:ok, response}
      end)

      result =
        Extractor.extract(@question_bank_text,
          source: :material,
          test_type: :sat,
          section_hint: "Cell Biology"
        )

      assert length(result) == 1
    end
  end

  describe "extract/2 — normalize_options with empty values" do
    test "strips options with empty string values" do
      response =
        Jason.encode!([
          %{
            "content" => "What is the function of the nucleus in a eukaryotic cell?",
            "answer" => "A",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "Contains DNA", "B" => "Makes ATP", "C" => "Digest food", "D" => ""},
            "difficulty" => "easy",
            "explanation" => "The nucleus houses genetic material."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      # D has empty value so after normalization only A, B, C remain (still >= 3)
      [q] = Extractor.extract(@question_bank_text, source: :material)
      assert map_size(q.options) == 3
      refute Map.has_key?(q.options, "D")
    end

    test "rejects MCQ when only empty-value options remain below the minimum" do
      response =
        Jason.encode!([
          %{
            "content" => "What does the Golgi apparatus do in the cell?",
            "answer" => "A",
            "question_type" => "multiple_choice",
            "options" => %{"A" => "Process proteins", "B" => "", "C" => "", "D" => ""},
            "difficulty" => "easy",
            "explanation" => "The Golgi modifies and packages proteins."
          }
        ])

      expect(ClientMock, :call, fn _sys, _usr, _opts -> {:ok, response} end)

      # After stripping blanks only 1 option remains → rejects MCQ
      assert [] = Extractor.extract(@question_bank_text, source: :material)
    end
  end
end
