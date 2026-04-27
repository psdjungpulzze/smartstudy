defmodule FunSheep.Scraper.SourceReputation do
  @moduledoc """
  Maps source domains to trust tiers and per-tier validation thresholds.

  Tier 1 — official test makers: the authoritative source for the test.
    Questions are real exam content; trust is high. Relaxed thresholds prevent
    rejecting legitimate questions for minor formatting issues.

  Tier 2 — established, widely-cited prep companies.
    High editorial standards but not the official test maker.

  Tier 3 — popular student-sharing sites (Quizlet, SparkNotes, etc.).
    Variable quality; community-sourced content. Standard thresholds apply.

  Tier 4 — unknown domain (default for anything not in the list above).
    Full strictness — identical to the legacy AI-validation thresholds.

  Thresholds:
    Tier 1: passed >= 75.0, review >= 60.0
    Tier 2: passed >= 82.0, review >= 65.0
    Tier 3: passed >= 90.0, review >= 70.0
    Tier 4: passed >= 95.0, review >= 70.0   (no regression for unknown sources)
  """

  @tier1 ~w(collegeboard.org ets.org mcat.org lsac.org act.org)
  @tier2 ~w(khanacademy.org albert.io varsitytutors.com prepscholar.com magoosh.com kaplan.com)
  @tier3 ~w(quizlet.com sparknotes.com studocu.com coursehero.com)

  @tier_thresholds %{
    1 => %{passed_threshold: 75.0, review_threshold: 60.0},
    2 => %{passed_threshold: 82.0, review_threshold: 65.0},
    3 => %{passed_threshold: 90.0, review_threshold: 70.0},
    4 => %{passed_threshold: 95.0, review_threshold: 70.0}
  }

  @doc """
  Returns `%{tier: 1..4, passed_threshold: float, review_threshold: float}`.

  Defaults to tier 4 (most strict) for nil, empty, or unrecognised URLs.
  Subdomain matching is included: `satsuite.collegeboard.org` → tier 1.
  """
  @spec score(String.t() | nil) :: %{tier: 1..4, passed_threshold: float, review_threshold: float}
  def score(nil), do: tier_map(4)
  def score(""), do: tier_map(4)

  def score(url) when is_binary(url) do
    host = extract_host(url)
    tier = classify_host(host)
    tier_map(tier)
  end

  @doc "Returns the integer tier (1–4) for a source URL."
  @spec tier(String.t() | nil) :: 1..4
  def tier(url), do: score(url).tier

  @doc """
  Returns `%{passed_threshold: float, review_threshold: float}` for the given tier integer.
  Used by `Validation.apply_verdict/3` to apply per-tier thresholds without a URL.
  """
  @spec thresholds_for_tier(1..4) :: %{passed_threshold: float, review_threshold: float}
  def thresholds_for_tier(tier) when tier in 1..4, do: @tier_thresholds[tier]
  def thresholds_for_tier(_), do: @tier_thresholds[4]

  @doc """
  Human-readable label for a tier number, suitable for inclusion in prompts.
  """
  @spec tier_label(1..4) :: String.t()
  def tier_label(1), do: "Tier 1 — official test maker (accept minor formatting issues; stem and answer accuracy take priority)"
  def tier_label(2), do: "Tier 2 — established prep company (slight leniency on formatting; apply standard content checks)"
  def tier_label(3), do: "Tier 3 — student-sharing site (apply standard strictness)"
  def tier_label(4), do: "Tier 4 — unknown source (apply full strictness)"

  # --- Private helpers ---

  defp tier_map(tier), do: Map.put(@tier_thresholds[tier], :tier, tier)

  defp extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host |> String.downcase() |> String.trim_leading("www.")

      _ ->
        ""
    end
  end

  defp classify_host(host) do
    cond do
      Enum.any?(@tier1, &host_matches?(host, &1)) -> 1
      Enum.any?(@tier2, &host_matches?(host, &1)) -> 2
      Enum.any?(@tier3, &host_matches?(host, &1)) -> 3
      true -> 4
    end
  end

  # Matches exact domain or any subdomain (e.g. satsuite.collegeboard.org → collegeboard.org)
  defp host_matches?(host, domain) do
    host == domain or String.ends_with?(host, "." <> domain)
  end
end
