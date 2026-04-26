defmodule FunSheep.Scraper.SiteExtractorTest do
  use ExUnit.Case, async: true

  alias FunSheep.Scraper.SiteExtractor
  alias FunSheep.Scraper.Extractors

  describe "extractor_for/1" do
    test "dispatches khanacademy.org to KhanAcademy extractor" do
      assert SiteExtractor.extractor_for("https://www.khanacademy.org/math/algebra") ==
               Extractors.KhanAcademy
    end

    test "dispatches varsitytutors.com to VarsityTutors extractor" do
      assert SiteExtractor.extractor_for("https://www.varsitytutors.com/sat_math-help") ==
               Extractors.VarsityTutors
    end

    test "dispatches albert.io to Albert extractor" do
      assert SiteExtractor.extractor_for("https://albert.io/learn/sat/math") ==
               Extractors.Albert
    end

    test "dispatches collegeboard.org to CollegeBoard extractor" do
      assert SiteExtractor.extractor_for("https://collegeboard.org/sat/practice") ==
               Extractors.CollegeBoard
    end

    test "dispatches satsuite.collegeboard.org to CollegeBoard extractor" do
      assert SiteExtractor.extractor_for("https://satsuite.collegeboard.org/sat") ==
               Extractors.CollegeBoard
    end

    test "falls back to Generic for unknown hosts" do
      assert SiteExtractor.extractor_for("https://example.com/questions") ==
               Extractors.Generic
    end

    test "falls back to Generic for subdomain of unknown host" do
      assert SiteExtractor.extractor_for("https://blog.somesite.com/sat-prep") ==
               Extractors.Generic
    end

    test "handles subdomain of known host" do
      assert SiteExtractor.extractor_for("https://exercises.khanacademy.org/path") ==
               Extractors.KhanAcademy
    end
  end

  describe "dispatch correctness — all registered domains" do
    test "every registered domain resolves to the expected module" do
      mappings = [
        {"https://khanacademy.org/math", Extractors.KhanAcademy},
        {"https://www.khanacademy.org/science", Extractors.KhanAcademy},
        {"https://varsitytutors.com/sat_math", Extractors.VarsityTutors},
        {"https://www.varsitytutors.com/sat-help", Extractors.VarsityTutors},
        {"https://albert.io/sat/math", Extractors.Albert},
        {"https://collegeboard.org/sat", Extractors.CollegeBoard},
        {"https://satsuite.collegeboard.org/sat", Extractors.CollegeBoard},
        {"https://unknown.edu/quizzes", Extractors.Generic},
        {"https://blog.randomprep.com/sat-tips", Extractors.Generic}
      ]

      for {url, expected_module} <- mappings do
        assert SiteExtractor.extractor_for(url) == expected_module,
               "Expected #{url} → #{expected_module}"
      end
    end
  end
end
