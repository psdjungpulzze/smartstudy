defmodule FunSheep.Scraper.Extractors.VarsityTutorsTest do
  use ExUnit.Case, async: true

  alias FunSheep.Scraper.Extractors.VarsityTutors

  @url "https://www.varsitytutors.com/sat_math-help/algebra"

  defp question_html(stem, choices, correct_class \\ "") do
    choice_lis =
      choices
      |> Enum.with_index()
      |> Enum.map(fn {{letter, text}, _idx} ->
        extra = if letter == correct_class, do: ~s( class="correct-answer"), else: ""
        ~s(<li class="answer-choice"#{extra}>#{text}</li>)
      end)
      |> Enum.join("\n")

    """
    <html><body>
      <div class="question-container">
        <div class="question-text">#{stem}</div>
        <ul>
          #{choice_lis}
        </ul>
      </div>
    </body></html>
    """
  end

  describe "extract/3 — structured VT question page" do
    test "extracts question stem and choices" do
      html = question_html(
        "If x + 3 = 7, what is the value of x?",
        [{"A", "2"}, {"B", "4"}, {"C", "6"}, {"D", "10"}]
      )

      assert {:ok, questions} = VarsityTutors.extract(html, @url, [])
      assert length(questions) == 1
      [q] = questions
      assert q.content =~ "x + 3 = 7"
      assert q.question_type == :multiple_choice
      assert map_size(q.options) >= 3
    end

    test "sets source metadata" do
      html = question_html(
        "Which of the following is equivalent to 3(x + 2)?",
        [{"A", "3x + 2"}, {"B", "3x + 6"}, {"C", "x + 6"}, {"D", "x + 2"}]
      )

      assert {:ok, [q]} = VarsityTutors.extract(html, @url, [])
      assert q.source_url == @url
      assert q.source_type == :web_scraped
      assert q.metadata["extractor"] == "varsity_tutors"
    end

    test "handles multiple question containers on one page" do
      html = """
      <html><body>
        <div class="question-container">
          <div class="question-text">If 2x = 10, what is the value of x?</div>
          <ul>
            <li class="answer-choice">3</li>
            <li class="answer-choice">5</li>
            <li class="answer-choice">7</li>
            <li class="answer-choice">9</li>
          </ul>
        </div>
        <div class="question-container">
          <div class="question-text">What is the slope of the line y = 3x + 2?</div>
          <ul>
            <li class="answer-choice">2</li>
            <li class="answer-choice">3</li>
            <li class="answer-choice">5</li>
            <li class="answer-choice">6</li>
          </ul>
        </div>
      </body></html>
      """

      assert {:ok, questions} = VarsityTutors.extract(html, @url, [])
      assert length(questions) == 2
    end
  end
end
