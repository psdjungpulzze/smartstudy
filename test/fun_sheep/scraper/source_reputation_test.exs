defmodule FunSheep.Scraper.SourceReputationTest do
  use ExUnit.Case, async: true

  alias FunSheep.Scraper.SourceReputation

  describe "score/1" do
    test "nil URL returns tier 4" do
      assert %{tier: 4, passed_threshold: 95.0, review_threshold: 70.0} = SourceReputation.score(nil)
    end

    test "empty string returns tier 4" do
      assert %{tier: 4} = SourceReputation.score("")
    end

    test "collegeboard.org is tier 1" do
      rep = SourceReputation.score("https://collegeboard.org/practice")
      assert rep.tier == 1
      assert rep.passed_threshold == 75.0
      assert rep.review_threshold == 60.0
    end

    test "subdomain of tier-1 domain (satsuite.collegeboard.org) is tier 1" do
      rep = SourceReputation.score("https://satsuite.collegeboard.org/sat/practice")
      assert rep.tier == 1
    end

    test "www subdomain is stripped correctly" do
      rep = SourceReputation.score("https://www.collegeboard.org/practice")
      assert rep.tier == 1
    end

    test "ets.org is tier 1" do
      assert %{tier: 1} = SourceReputation.score("https://ets.org/gre/practice")
    end

    test "act.org is tier 1" do
      assert %{tier: 1} = SourceReputation.score("https://act.org/content/act/en/products-and-services/the-act/test-preparation/free-act-test-prep.html")
    end

    test "khanacademy.org is tier 2" do
      rep = SourceReputation.score("https://www.khanacademy.org/sat")
      assert rep.tier == 2
      assert rep.passed_threshold == 82.0
      assert rep.review_threshold == 65.0
    end

    test "albert.io is tier 2" do
      assert %{tier: 2} = SourceReputation.score("https://albert.io/learn/sat/practice")
    end

    test "varsitytutors.com is tier 2" do
      assert %{tier: 2} = SourceReputation.score("https://www.varsitytutors.com/sat_math-practice-tests")
    end

    test "quizlet.com is tier 3" do
      rep = SourceReputation.score("https://quizlet.com/gb/513839481/sat-math-practice-flash-cards/")
      assert rep.tier == 3
      assert rep.passed_threshold == 90.0
      assert rep.review_threshold == 70.0
    end

    test "sparknotes.com is tier 3" do
      assert %{tier: 3} = SourceReputation.score("https://www.sparknotes.com/test-prep/sat/math/")
    end

    test "unknown domain is tier 4" do
      rep = SourceReputation.score("https://randomtestsite.edu/practice/sat-math")
      assert rep.tier == 4
      assert rep.passed_threshold == 95.0
      assert rep.review_threshold == 70.0
    end

    test "tier map includes all three keys" do
      rep = SourceReputation.score("https://collegeboard.org")
      assert Map.has_key?(rep, :tier)
      assert Map.has_key?(rep, :passed_threshold)
      assert Map.has_key?(rep, :review_threshold)
    end

    test "malformed URL defaults to tier 4" do
      assert %{tier: 4} = SourceReputation.score("not-a-url")
    end
  end

  describe "tier/1" do
    test "returns just the integer tier" do
      assert SourceReputation.tier("https://collegeboard.org") == 1
      assert SourceReputation.tier("https://khanacademy.org") == 2
      assert SourceReputation.tier("https://quizlet.com") == 3
      assert SourceReputation.tier("https://unknown.example.com") == 4
      assert SourceReputation.tier(nil) == 4
    end
  end

  describe "tier_label/1" do
    test "returns a non-empty string for each tier" do
      for tier <- 1..4 do
        label = SourceReputation.tier_label(tier)
        assert is_binary(label)
        assert String.length(label) > 0
      end
    end

    test "tier 1 label mentions 'official'" do
      assert SourceReputation.tier_label(1) =~ "official"
    end

    test "tier 4 label mentions 'full strictness'" do
      assert SourceReputation.tier_label(4) =~ "full strictness"
    end
  end
end
