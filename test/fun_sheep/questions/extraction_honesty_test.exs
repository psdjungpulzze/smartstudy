defmodule FunSheep.Questions.ExtractionHonestyTest do
  @moduledoc """
  Phase 7.3 — Extraction honesty test.

  For each site-specific extractor, verifies that every extracted question's
  `content` field is derived from text that actually appears in the source HTML.
  This is the automated enforcement of criterion 2: "not creation".

  An extractor that fabricates content not present in the input HTML fails here.
  """

  use ExUnit.Case, async: true

  alias FunSheep.Scraper.Extractors.{KhanAcademy, VarsityTutors, Albert, CollegeBoard}

  @fixtures_root Path.expand("../../fixtures/scraper", __DIR__)

  defp read_fixture(site, file), do: File.read!(Path.join([@fixtures_root, site, file]))

  # Returns true if at least one word from `content` appears in `html`.
  # We use a loose "any meaningful word" check since extractors may normalise
  # whitespace, strip markup, or rephrase with minor cleanup.
  defp content_grounded_in?(content, html) when is_binary(content) and is_binary(html) do
    words =
      content
      |> String.split(~r/[\s\$\[\]\\,\.\?!:;(){}="']+/, trim: true)
      |> Enum.filter(&(String.length(&1) >= 6))
      |> Enum.uniq()

    # Every significant word should appear somewhere in the raw HTML
    if words == [] do
      true
    else
      Enum.all?(words, fn w -> String.contains?(html, w) end)
    end
  end

  describe "KhanAcademy extractor — honesty" do
    test "extracted content words are present in the source HTML" do
      html = read_fixture("khan_academy", "exercise_page.html")
      {:ok, questions} = KhanAcademy.extract(html, "https://www.khanacademy.org/math/algebra", [])

      Enum.each(questions, fn q ->
        assert content_grounded_in?(q.content, html),
               "[KhanAcademy] Fabricated content not in source HTML: #{inspect(q.content)}"
      end)
    end
  end

  describe "VarsityTutors extractor — honesty" do
    test "extracted content words are present in the source HTML" do
      html = read_fixture("varsity_tutors", "question_page.html")
      {:ok, questions} = VarsityTutors.extract(html, "https://www.varsitytutors.com/sat_math", [])

      Enum.each(questions, fn q ->
        assert content_grounded_in?(q.content, html),
               "[VarsityTutors] Fabricated content not in source HTML: #{inspect(q.content)}"
      end)
    end

    test "extracted answers are present in the source HTML" do
      html = read_fixture("varsity_tutors", "question_page.html")
      {:ok, questions} = VarsityTutors.extract(html, "https://www.varsitytutors.com/sat_math", [])

      Enum.each(questions, fn q ->
        if is_binary(q.answer) and String.length(q.answer) > 2 do
          assert String.contains?(html, q.answer),
                 "[VarsityTutors] Answer not found in source HTML: #{inspect(q.answer)}"
        end
      end)
    end
  end

  describe "Albert extractor — honesty" do
    test "extracted content words are present in the source HTML" do
      html = read_fixture("albert", "question_page.html")
      {:ok, questions} = Albert.extract(html, "https://albert.io/learn/ap-biology", [])

      Enum.each(questions, fn q ->
        assert content_grounded_in?(q.content, html),
               "[Albert] Fabricated content not in source HTML: #{inspect(q.content)}"
      end)
    end
  end

  describe "CollegeBoard extractor — honesty" do
    test "extracted content words are present in the source HTML" do
      html = read_fixture("college_board", "question_page.html")
      {:ok, questions} = CollegeBoard.extract(html, "https://satsuite.collegeboard.org/sat", [])

      Enum.each(questions, fn q ->
        assert content_grounded_in?(q.content, html),
               "[CollegeBoard] Fabricated content not in source HTML: #{inspect(q.content)}"
      end)
    end
  end
end
