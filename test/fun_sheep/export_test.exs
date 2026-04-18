defmodule FunSheep.ExportTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Export

  describe "export_study_guide_text/1" do
    test "produces correct format with sections" do
      guide = %{
        content: %{
          "title" => "Biology Study Guide",
          "generated_for" => "Biology 101",
          "test_date" => "2026-04-25",
          "aggregate_score" => 75,
          "sections" => [
            %{
              "chapter_name" => "Cell Biology",
              "priority" => "High",
              "score" => 60,
              "review_topics" => ["Mitosis", "Cell Membrane"],
              "wrong_questions" => [
                %{"content" => "What is ATP?", "answer" => "Adenosine triphosphate"}
              ]
            },
            %{
              "chapter_name" => "Genetics",
              "priority" => "Low",
              "score" => 90,
              "review_topics" => ["DNA Replication"],
              "wrong_questions" => []
            }
          ]
        }
      }

      text = Export.export_study_guide_text(guide)

      assert text =~ "# Biology Study Guide"
      assert text =~ "Course: Biology 101"
      assert text =~ "Test Date: 2026-04-25"
      assert text =~ "Overall Readiness: 75%"
      assert text =~ "## Cell Biology (High Priority - 60%)"
      assert text =~ "- Mitosis"
      assert text =~ "- Cell Membrane"
      assert text =~ "### Questions to Review"
      assert text =~ "**Q:** What is ATP?"
      assert text =~ "**A:** Adenosine triphosphate"
      assert text =~ "## Genetics (Low Priority - 90%)"
      assert text =~ "- DNA Replication"
    end

    test "handles empty sections" do
      guide = %{content: %{"title" => "Empty Guide", "sections" => []}}
      text = Export.export_study_guide_text(guide)

      assert text =~ "# Empty Guide"
      # Should not crash
      assert is_binary(text)
    end

    test "handles nil content gracefully" do
      guide = %{content: nil}
      text = Export.export_study_guide_text(guide)

      assert text =~ "# Study Guide"
      assert is_binary(text)
    end
  end

  describe "export_readiness_report_text/3" do
    test "produces correct format" do
      chapter_id = Ecto.UUID.generate()

      schedule = %{name: "Midterm", test_date: ~D[2026-04-25]}

      readiness = %{
        aggregate_score: 72.5,
        chapter_scores: %{chapter_id => 85.0}
      }

      chapters = [
        %{id: chapter_id, name: "Chapter 1"}
      ]

      text = Export.export_readiness_report_text(schedule, readiness, chapters)

      assert text =~ "# Test Readiness Report"
      assert text =~ "Test: Midterm"
      assert text =~ "Date: 2026-04-25"
      assert text =~ "Overall Score: 72.5%"
      assert text =~ "## Chapter Scores"
      assert text =~ "- Chapter 1: 85.0% (Ready)"
    end

    test "shows correct status labels" do
      ch1_id = Ecto.UUID.generate()
      ch2_id = Ecto.UUID.generate()
      ch3_id = Ecto.UUID.generate()

      schedule = %{name: "Quiz", test_date: ~D[2026-05-01]}

      readiness = %{
        aggregate_score: 50.0,
        chapter_scores: %{
          ch1_id => 80.0,
          ch2_id => 50.0,
          ch3_id => 20.0
        }
      }

      chapters = [
        %{id: ch1_id, name: "Ready Chapter"},
        %{id: ch2_id, name: "Needs Work Chapter"},
        %{id: ch3_id, name: "Critical Chapter"}
      ]

      text = Export.export_readiness_report_text(schedule, readiness, chapters)

      assert text =~ "Ready Chapter: 80.0% (Ready)"
      assert text =~ "Needs Work Chapter: 50.0% (Needs Work)"
      assert text =~ "Critical Chapter: 20.0% (Critical)"
    end

    test "handles empty chapters" do
      schedule = %{name: "Test", test_date: ~D[2026-05-01]}
      readiness = %{aggregate_score: 0.0, chapter_scores: %{}}

      text = Export.export_readiness_report_text(schedule, readiness, [])

      assert text =~ "# Test Readiness Report"
      assert is_binary(text)
    end
  end
end
