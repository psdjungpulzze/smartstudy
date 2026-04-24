defmodule FunSheep.Seeds.EssayRubricSeeds do
  @moduledoc """
  Seed data for essay rubric templates.

  IMPORTANT: These are generic PRACTICE rubrics inspired by common exam formats.
  They are NOT official scoring guides from College Board, ETS, NCBE, or ACT.
  Official rubrics require admin-authored content with proper licensing.
  These serve as reasonable starting points for student practice only.
  """

  def run do
    alias FunSheep.Repo
    alias FunSheep.Essays.EssayRubricTemplate

    templates = [
      %{
        name: "AP English Language & Composition (Practice)",
        exam_type: "ap_eng_lang",
        max_score: 6,
        mastery_threshold_ratio: 0.67,
        time_limit_minutes: 40,
        word_target: 500,
        word_limit: nil,
        criteria: [
          %{
            name: "Thesis",
            max_points: 1,
            description:
              "Presents a defensible claim responding to the prompt"
          },
          %{
            name: "Evidence & Commentary",
            max_points: 4,
            description:
              "Selects evidence and explains how it supports the line of reasoning"
          },
          %{
            name: "Sophistication",
            max_points: 1,
            description:
              "Demonstrates nuanced understanding or purposeful stylistic choices"
          }
        ]
      },
      %{
        name: "GRE Analytical Writing (Practice)",
        exam_type: "gre_aw",
        max_score: 6,
        mastery_threshold_ratio: 0.67,
        time_limit_minutes: 30,
        word_target: 500,
        word_limit: nil,
        criteria: [
          %{
            name: "Holistic Score",
            max_points: 6,
            description:
              "Holistic 0–6: insightful analysis, well-organized, precise language"
          }
        ]
      },
      %{
        name: "Bar Exam MEE (Practice)",
        exam_type: "bar_mee",
        max_score: 6,
        mastery_threshold_ratio: 0.5,
        time_limit_minutes: 30,
        word_target: 400,
        word_limit: nil,
        criteria: [
          %{
            name: "Issue Identification",
            max_points: 1,
            description: "Correctly identifies the legal issues presented"
          },
          %{
            name: "Rule Statement",
            max_points: 2,
            description: "States the applicable legal rules accurately"
          },
          %{
            name: "Application",
            max_points: 2,
            description: "Applies rules to facts; IRAC structure followed"
          },
          %{
            name: "Conclusion",
            max_points: 1,
            description: "Reaches a logical conclusion given the analysis"
          }
        ]
      },
      %{
        name: "Generic Essay",
        exam_type: "generic",
        max_score: 10,
        mastery_threshold_ratio: 0.67,
        time_limit_minutes: 40,
        word_target: 500,
        word_limit: nil,
        criteria: [
          %{
            name: "Thesis & Argument",
            max_points: 3,
            description: "Clear thesis with a defensible claim"
          },
          %{
            name: "Evidence & Support",
            max_points: 3,
            description: "Relevant evidence with analysis"
          },
          %{
            name: "Organization",
            max_points: 2,
            description: "Logical structure and coherent flow"
          },
          %{
            name: "Language & Style",
            max_points: 2,
            description: "Appropriate academic register and clarity"
          }
        ]
      }
    ]

    Enum.each(templates, fn attrs ->
      Repo.insert!(
        %EssayRubricTemplate{} |> EssayRubricTemplate.changeset(attrs),
        on_conflict: {:replace, [:name, :criteria, :mastery_threshold_ratio, :updated_at]},
        conflict_target: :exam_type
      )
    end)

    IO.puts("[EssayRubricSeeds] Inserted #{length(templates)} rubric templates.")
  end
end
