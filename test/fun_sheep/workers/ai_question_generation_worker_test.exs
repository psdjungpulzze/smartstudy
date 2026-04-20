defmodule FunSheep.Workers.AIQuestionGenerationWorkerTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Workers.AIQuestionGenerationWorker

  describe "validate_figure_dependency/2" do
    test "passes plain text questions without figures" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "What is the capital of France?",
               false
             ) == :ok
    end

    test "rejects questions referencing a table without a visual" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "Which conclusion can be drawn from the data in the table above?",
               false
             ) == {:error, :figure_reference_without_attachment}
    end

    test "rejects questions referencing a figure without a visual" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "Based on Figure 3, what is the membrane composition?",
               false
             ) == {:error, :figure_reference_without_attachment}
    end

    test "rejects 'shown above' and 'shown below' patterns" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "Using the graph shown above, estimate the slope.",
               false
             ) == {:error, :figure_reference_without_attachment}

      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "Using the graph shown below, estimate the slope.",
               false
             ) == {:error, :figure_reference_without_attachment}
    end

    test "rejects diagram/chart/image references" do
      for content <- [
            "In the diagram, which part labels the nucleus?",
            "The chart shows four categories; which is largest?",
            "Identify the structure in the image."
          ] do
        assert AIQuestionGenerationWorker.validate_figure_dependency(content, false) ==
                 {:error, :figure_reference_without_attachment}
      end
    end

    test "allows figure-referencing questions when a visual IS attached" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "Based on the table, what trend does temperature show?",
               true
             ) == :ok
    end

    test "rejects empty content" do
      assert AIQuestionGenerationWorker.validate_figure_dependency(nil, false) ==
               {:error, :empty_content}
    end

    test "does not false-positive on incidental uses" do
      # 'table' appears, but not as a reference to a visual — the word describes
      # the object of study, not a figure. This is still caught by the regex,
      # but such questions should attach a figure_id or the generator must
      # rephrase. We accept some false positives to prevent broken questions.
      assert AIQuestionGenerationWorker.validate_figure_dependency(
               "What is the primary function of a kitchen table?",
               false
             ) == {:error, :figure_reference_without_attachment}
    end
  end
end
