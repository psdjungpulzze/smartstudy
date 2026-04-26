defmodule FunSheep.Workers.VolumeRegressionTest do
  @moduledoc """
  Phase 7.4 — Volume regression test.

  Runs the extractor layer against a fixed set of 50 fixture URLs covering
  all supported domains. Asserts that at least 40 of those URLs (80%) yield
  at least one question. This guards against extractor regressions that
  silently drop yield across the fleet.

  Runs async because it only calls pure extraction functions (no DB, no HTTP).
  Not tagged :slow so it runs on every PR, but it completes in under 1 second.
  """

  use ExUnit.Case, async: true

  alias FunSheep.Scraper.SiteExtractor

  @fixtures_root Path.expand("../../fixtures/scraper", __DIR__)

  defp read_fixture(site, file), do: File.read!(Path.join([@fixtures_root, site, file]))

  # A representative URL → fixture-file mapping covering all 4 supported extractors.
  # 50 entries: 13 KA exercise, 4 KA category (expected no-yield), 11 VarsityTutors,
  #             11 Albert, 11 CollegeBoard.
  # Expected yield: 46/50 = 92% — well above the 80% guard-rail.
  @fixture_urls [
    # KhanAcademy exercise pages (expected yield: yes)
    {"https://www.khanacademy.org/math/algebra/exercise-1", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/algebra/exercise-2", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/algebra/exercise-3", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/geometry/exercise-1", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/geometry/exercise-2", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/geometry/exercise-3", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/science/biology/exercise-1", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/science/biology/exercise-2", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/science/chemistry/exercise-1", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/science/chemistry/exercise-2", "khan_academy",
     "exercise_page.html"},
    {"https://www.khanacademy.org/math/sat/exercise-1", "khan_academy", "exercise_page.html"},
    {"https://www.khanacademy.org/math/sat/exercise-2", "khan_academy", "exercise_page.html"},
    {"https://www.khanacademy.org/math/sat/exercise-3", "khan_academy", "exercise_page.html"},
    # KhanAcademy category/listing pages (expected yield: no — no Perseus data)
    {"https://www.khanacademy.org/math/algebra", "khan_academy", "category_page.html"},
    {"https://www.khanacademy.org/math/geometry", "khan_academy", "category_page.html"},
    {"https://www.khanacademy.org/science/biology", "khan_academy", "category_page.html"},
    {"https://www.khanacademy.org/math/sat", "khan_academy", "category_page.html"},
    # VarsityTutors (expected yield: yes)
    {"https://www.varsitytutors.com/sat_math-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/sat_reading-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/sat_writing-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/act_math-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/act_science-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/act_reading-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/ap_biology-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/ap_chemistry-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/ap_calculus_ab-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/gre_math-practice-tests", "varsity_tutors",
     "question_page.html"},
    {"https://www.varsitytutors.com/gre_verbal-practice-tests", "varsity_tutors",
     "question_page.html"},
    # Albert (expected yield: yes)
    {"https://albert.io/learn/ap-biology", "albert", "question_page.html"},
    {"https://albert.io/learn/ap-chemistry", "albert", "question_page.html"},
    {"https://albert.io/learn/ap-calculus-ab", "albert", "question_page.html"},
    {"https://albert.io/learn/ap-us-history", "albert", "question_page.html"},
    {"https://albert.io/learn/sat-math", "albert", "question_page.html"},
    {"https://albert.io/learn/sat-reading", "albert", "question_page.html"},
    {"https://albert.io/learn/act-math", "albert", "question_page.html"},
    {"https://albert.io/learn/act-science", "albert", "question_page.html"},
    {"https://albert.io/learn/act-reading", "albert", "question_page.html"},
    {"https://albert.io/learn/gre-math", "albert", "question_page.html"},
    {"https://albert.io/learn/gre-verbal", "albert", "question_page.html"},
    # CollegeBoard (expected yield: yes)
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/1",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/2",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/3",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/4",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/5",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/6",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/7",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/paper/8",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/digital/1",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/digital/2",
     "college_board", "question_page.html"},
    {"https://satsuite.collegeboard.org/sat/practice/full-length-practice-tests/digital/3",
     "college_board", "question_page.html"}
  ]

  @total_urls length(@fixture_urls)
  @min_yield_rate 0.80

  describe "extraction yield across fixture set" do
    test "≥80% of fixture URLs yield at least one question" do
      results =
        Enum.map(@fixture_urls, fn {url, site, file} ->
          html = read_fixture(site, file)
          {:ok, questions} = SiteExtractor.extract(html, url, [])
          {url, length(questions)}
        end)

      yielding = Enum.count(results, fn {_url, count} -> count > 0 end)
      yield_rate = yielding / @total_urls

      failing_urls =
        results
        |> Enum.filter(fn {_url, count} -> count == 0 end)
        |> Enum.map(fn {url, _} -> "  - #{url}" end)
        |> Enum.join("\n")

      assert yield_rate >= @min_yield_rate,
             "Yield rate #{Float.round(yield_rate * 100, 1)}% < #{trunc(@min_yield_rate * 100)}% required.\n" <>
               "Zero-yield URLs (#{@total_urls - yielding}/#{@total_urls}):\n#{failing_urls}"
    end

    test "no extracted question is tagged is_generated: true" do
      Enum.each(@fixture_urls, fn {url, site, file} ->
        html = read_fixture(site, file)
        {:ok, questions} = SiteExtractor.extract(html, url, [])

        Enum.each(questions, fn q ->
          refute Map.get(q, :is_generated, false),
                 "Extractor for #{url} produced is_generated: true on question: #{inspect(q.content)}"
        end)
      end)
    end
  end
end
