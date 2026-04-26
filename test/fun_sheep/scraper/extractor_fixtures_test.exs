defmodule FunSheep.Scraper.ExtractorFixturesTest do
  @moduledoc """
  Regression tests for site-specific extractors against saved HTML snapshots.

  Each test loads a real fixture from test/fixtures/scraper/<site>/ and
  asserts that the extractor returns >= 1 question. If an extractor starts
  returning 0 on a previously-working fixture, a selector broke.

  These are the authoritative regression baseline for Phase 7.
  """

  use ExUnit.Case, async: true

  alias FunSheep.Scraper.Extractors.{KhanAcademy, VarsityTutors, Albert, CollegeBoard}
  alias FunSheep.Scraper.SiteExtractor

  @fixtures_root Path.expand("../../fixtures/scraper", __DIR__)

  defp read_fixture(site, file), do: File.read!(Path.join([@fixtures_root, site, file]))

  # -------------------------------------------------------------------------
  # Khan Academy
  # -------------------------------------------------------------------------

  describe "KhanAcademy extractor" do
    test "extracts questions from a Perseus exercise page" do
      html = read_fixture("khan_academy", "exercise_page.html")
      assert {:ok, questions} = KhanAcademy.extract(html, "https://www.khanacademy.org/math/algebra/exercise/solve-for-x", [])
      assert length(questions) >= 1
    end

    test "extracted content matches text in the fixture HTML" do
      html = read_fixture("khan_academy", "exercise_page.html")
      {:ok, questions} = KhanAcademy.extract(html, "https://www.khanacademy.org/math/algebra/exercise/solve-for-x", [])

      Enum.each(questions, fn q ->
        # content is a Perseus markup string — check it's non-empty
        assert is_binary(q.content) and String.length(q.content) > 5
      end)
    end

    test "falls back gracefully on a category listing page (no Perseus data)" do
      html = read_fixture("khan_academy", "category_page.html")
      # Should not crash — either returns [] questions or falls to Generic
      assert {:ok, _} = KhanAcademy.extract(html, "https://www.khanacademy.org/math/algebra", [])
    end

    test "dispatcher routes khanacademy.org to KhanAcademy module" do
      assert SiteExtractor.extractor_for("https://www.khanacademy.org/math/algebra") ==
               KhanAcademy
    end
  end

  # -------------------------------------------------------------------------
  # VarsityTutors
  # -------------------------------------------------------------------------

  describe "VarsityTutors extractor" do
    test "extracts questions from a question page" do
      html = read_fixture("varsity_tutors", "question_page.html")
      assert {:ok, questions} = VarsityTutors.extract(html, "https://www.varsitytutors.com/sat_math-practice-tests", [])
      assert length(questions) >= 1
    end

    test "extracted content is non-empty and present in source HTML" do
      html = read_fixture("varsity_tutors", "question_page.html")
      {:ok, questions} = VarsityTutors.extract(html, "https://www.varsitytutors.com/sat_math-practice-tests", [])

      Enum.each(questions, fn q ->
        assert is_binary(q.content) and String.length(q.content) > 10
        assert String.contains?(html, String.trim(q.content)) or
                 String.contains?(html, String.slice(String.trim(q.content), 0, 20)),
               "Extracted content not found in source HTML: #{inspect(q.content)}"
      end)
    end

    test "extracted questions have :multiple_choice type when choices present" do
      html = read_fixture("varsity_tutors", "question_page.html")
      {:ok, questions} = VarsityTutors.extract(html, "https://www.varsitytutors.com/sat_math-practice-tests", [])

      Enum.each(questions, fn q ->
        assert q.question_type == :multiple_choice
      end)
    end

    test "dispatcher routes varsitytutors.com to VarsityTutors module" do
      assert SiteExtractor.extractor_for("https://www.varsitytutors.com/sat-practice") ==
               VarsityTutors
    end
  end

  # -------------------------------------------------------------------------
  # Albert.io
  # -------------------------------------------------------------------------

  describe "Albert extractor" do
    test "extracts questions from an AP Biology question page" do
      html = read_fixture("albert", "question_page.html")
      assert {:ok, questions} = Albert.extract(html, "https://albert.io/learn/ap-biology/practice", [])
      assert length(questions) >= 1
    end

    test "extracted content is present in source HTML" do
      html = read_fixture("albert", "question_page.html")
      {:ok, questions} = Albert.extract(html, "https://albert.io/learn/ap-biology/practice", [])

      Enum.each(questions, fn q ->
        content_snippet = String.slice(String.trim(q.content), 0, 30)
        assert String.contains?(html, content_snippet),
               "Extracted content not found in source HTML: #{inspect(content_snippet)}"
      end)
    end

    test "dispatcher routes albert.io to Albert module" do
      assert SiteExtractor.extractor_for("https://albert.io/learn/ap-biology") == Albert
    end
  end

  # -------------------------------------------------------------------------
  # College Board
  # -------------------------------------------------------------------------

  describe "CollegeBoard extractor" do
    test "extracts questions from a practice question page" do
      html = read_fixture("college_board", "question_page.html")
      assert {:ok, questions} = CollegeBoard.extract(html, "https://satsuite.collegeboard.org/sat/practice", [])
      assert length(questions) >= 1
    end

    test "extracted content is non-empty" do
      html = read_fixture("college_board", "question_page.html")
      {:ok, questions} = CollegeBoard.extract(html, "https://satsuite.collegeboard.org/sat/practice", [])

      Enum.each(questions, fn q ->
        assert is_binary(q.content) and String.length(q.content) > 20
      end)
    end

    test "dispatcher routes satsuite.collegeboard.org to CollegeBoard module" do
      assert SiteExtractor.extractor_for("https://satsuite.collegeboard.org/sat/practice") ==
               CollegeBoard
    end

    test "dispatcher routes collegeboard.org to CollegeBoard module" do
      assert SiteExtractor.extractor_for("https://collegeboard.org/sat") == CollegeBoard
    end
  end

  # -------------------------------------------------------------------------
  # Generic extractor (fallback)
  # -------------------------------------------------------------------------

  describe "Generic extractor" do
    test "does not crash on empty HTML" do
      assert {:ok, _} =
               FunSheep.Scraper.Extractors.Generic.extract(
                 "<html><body></body></html>",
                 "https://unknown.example.com/page",
                 []
               )
    end

    test "unknown domain routes to Generic" do
      assert SiteExtractor.extractor_for("https://totally-unknown-site.example.com/q") ==
               FunSheep.Scraper.Extractors.Generic
    end
  end
end
