defmodule FunSheep.Gamification.FpEconomy do
  @moduledoc """
  Canonical Fleece Points (FP) economy: per-source award amounts, level curve,
  and streak milestones.

  Single source of truth for the values the UI displays in the "Earn more FP"
  panel and level meter. Existing LiveView modules (`practice_live`,
  `assessment_live`, `quick_test_live`, `daily_challenge_live`, `review_live`,
  `engagement/study_sessions`) reference these constants so award amounts can
  never drift from what is shown to students.
  """

  # Per-correct base award shared across question-driven activities.
  @xp_per_correct 10

  # Per-card award for spaced-repetition review.
  @xp_per_review_card 10

  # Daily Shear (5-question challenge).
  @daily_challenge_question_count 5
  @daily_challenge_xp_per_correct 20
  @daily_challenge_xp_bonus_perfect 50

  # Study session base economy (lib/fun_sheep/engagement/study_sessions.ex).
  @study_session_xp_per_correct 5
  @study_session_completion_bonus 10
  @study_session_all_windows_bonus 25
  @study_session_all_windows_threshold 3

  @study_session_time_window_multipliers %{
    "morning" => 2.0,
    "afternoon" => 1.5,
    "evening" => 1.0,
    "night" => 1.0
  }

  # Streak milestones — must match Gamification.check_streak_achievements/1.
  @streak_milestones [3, 7, 14, 30, 100]

  # Level curve (FP threshold → level). Sheep-themed names map to the mascot.
  @levels [
    {1, 0, "Lamb"},
    {2, 100, "Spring Lamb"},
    {3, 250, "Yearling"},
    {4, 500, "Shearling"},
    {5, 1_000, "Ewe"},
    {6, 2_000, "Ram"},
    {7, 4_000, "Flockmaster"},
    {8, 7_500, "Goldenfleece"},
    {9, 12_500, "Master Shepherd"},
    {10, 20_000, "Legendary Sheep"}
  ]

  ## ── Per-source amounts ───────────────────────────────────────────────────

  def xp_per_correct, do: @xp_per_correct
  def xp_per_review_card, do: @xp_per_review_card

  def daily_challenge_question_count, do: @daily_challenge_question_count
  def daily_challenge_xp_per_correct, do: @daily_challenge_xp_per_correct
  def daily_challenge_xp_bonus_perfect, do: @daily_challenge_xp_bonus_perfect

  def study_session_xp_per_correct, do: @study_session_xp_per_correct
  def study_session_completion_bonus, do: @study_session_completion_bonus
  def study_session_all_windows_bonus, do: @study_session_all_windows_bonus
  def study_session_all_windows_threshold, do: @study_session_all_windows_threshold
  def study_session_time_window_multipliers, do: @study_session_time_window_multipliers

  def streak_milestones, do: @streak_milestones

  @doc """
  Returns the next streak milestone above `current_streak`, or `nil` if the
  user is already at the highest milestone.
  """
  def next_streak_milestone(current_streak) when is_integer(current_streak) do
    Enum.find(@streak_milestones, fn m -> m > current_streak end)
  end

  ## ── "Earn more FP" rules ─────────────────────────────────────────────────

  @doc """
  Returns the canonical list of FP-earning activities for the "Earn more"
  section of the FP modal. Each entry contains a key, label, real amount
  formula, source slug (matches `XpEvent.source`), and a CTA target.

  All amounts derive from the constants above — no values are hardcoded
  in templates.
  """
  def earn_more_rules do
    [
      %{
        key: :quick_test,
        source: "quick_test",
        icon: "⚡",
        label: "Quick Test",
        amount_label: "+#{@xp_per_correct} FP per correct",
        description: "Fast-fire questions on any course",
        cta_label: "Start a Quick Test",
        cta_path: "/dashboard"
      },
      %{
        key: :practice,
        source: "practice",
        icon: "🎯",
        label: "Practice",
        amount_label: "+#{@xp_per_correct} FP per correct",
        description: "Targeted practice on weak topics",
        cta_label: "Practice now",
        cta_path: "/dashboard"
      },
      %{
        key: :daily_challenge,
        source: "daily_challenge",
        icon: "🔥",
        label: "Daily Shear",
        amount_label:
          "+#{@daily_challenge_xp_per_correct} FP per correct, +#{@daily_challenge_xp_bonus_perfect} bonus for a perfect #{@daily_challenge_question_count}/#{@daily_challenge_question_count}",
        description: "One short challenge per day per course",
        cta_label: "Take today's Daily Shear",
        cta_path: "/dashboard"
      },
      %{
        key: :review,
        source: "review",
        icon: "🧠",
        label: "Review (Spaced Repetition)",
        amount_label: "+#{@xp_per_review_card} FP per card",
        description: "Lock in what you've learned before you forget",
        cta_label: "Review due cards",
        cta_path: "/review"
      },
      %{
        key: :assessment,
        source: "assessment",
        icon: "📝",
        label: "Assessment",
        amount_label: "+#{@xp_per_correct} FP per correct",
        description: "Full-length course assessment",
        cta_label: "Take an assessment",
        cta_path: "/dashboard"
      },
      %{
        key: :study_session,
        source: "study_session",
        icon: "🌅",
        label: "Study at peak hours",
        amount_label:
          "Morning #{format_mult(@study_session_time_window_multipliers["morning"])}, Afternoon #{format_mult(@study_session_time_window_multipliers["afternoon"])}, +#{@study_session_all_windows_bonus} FP if you study #{@study_session_all_windows_threshold}+ windows in a day",
        description: "Time-window multipliers stack on session XP",
        cta_label: "Start a study session",
        cta_path: "/dashboard"
      }
    ]
  end

  defp format_mult(1.0), do: "×1"
  defp format_mult(mult) when is_float(mult), do: "×#{:erlang.float_to_binary(mult, decimals: 1)}"

  ## ── Level curve ──────────────────────────────────────────────────────────

  def levels, do: @levels

  @doc """
  Returns the user's current level info for a given total FP.

  Returns a map with `:level`, `:name`, `:current_threshold`,
  `:next_threshold` (nil at max level), `:fp_into_level`,
  `:fp_to_next_level` (nil at max), and `:progress_pct` (0..100).
  """
  def level_for_xp(total_xp) when is_integer(total_xp) and total_xp >= 0 do
    {current, next} = find_level_pair(total_xp)
    {level, current_threshold, name} = current

    case next do
      nil ->
        %{
          level: level,
          name: name,
          current_threshold: current_threshold,
          next_threshold: nil,
          fp_into_level: total_xp - current_threshold,
          fp_to_next_level: nil,
          progress_pct: 100
        }

      {_next_level, next_threshold, _next_name} ->
        span = next_threshold - current_threshold
        into = total_xp - current_threshold
        pct = if span > 0, do: round(into * 100 / span), else: 0

        %{
          level: level,
          name: name,
          current_threshold: current_threshold,
          next_threshold: next_threshold,
          fp_into_level: into,
          fp_to_next_level: next_threshold - total_xp,
          progress_pct: max(0, min(100, pct))
        }
    end
  end

  defp find_level_pair(total_xp) do
    Enum.reduce_while(Enum.with_index(@levels), nil, fn {{lvl, threshold, name}, idx}, _acc ->
      next = Enum.at(@levels, idx + 1)

      cond do
        next == nil ->
          {:halt, {{lvl, threshold, name}, nil}}

        total_xp < elem(next, 1) ->
          {:halt, {{lvl, threshold, name}, next}}

        true ->
          {:cont, nil}
      end
    end)
  end
end
