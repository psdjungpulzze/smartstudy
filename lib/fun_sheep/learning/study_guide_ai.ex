defmodule FunSheep.Learning.StudyGuideAI do
  @moduledoc """
  On-demand AI content generation for study guides.

  Generates explanations for wrong questions and chapter concept summaries
  via the Interactor AI agents platform. Returns mock content in mock mode.

  This is the "lazy" part of the hybrid approach — content is generated
  when the student clicks to expand, not at guide creation time.
  """

  require Logger

  @system_prompt "You are a patient, encouraging educational tutor. Explain concepts clearly and concisely using simple language and concrete examples. Keep explanations conversational and motivating. Return plain text only."

  @llm_opts %{
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1_024,
    temperature: 0.7,
    source: "study_guide_ai"
  }

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)

  @doc """
  Generates an explanation for why a question's answer is correct,
  and what misconception likely led to the wrong answer.

  Returns `{:ok, explanation_text}` or `{:error, reason}`.
  """
  def explain_question(question_content, correct_answer, opts \\ []) do
    subject = opts[:subject] || "the subject"
    chapter = opts[:chapter] || "this topic"

    if mock_mode?() do
      {:ok, mock_explanation(question_content, correct_answer, chapter)}
    else
      prompt = """
      You are a patient, encouraging #{subject} tutor helping a student understand why they got a question wrong.

      **Question:** #{question_content}
      **Correct Answer:** #{correct_answer}
      **Chapter/Topic:** #{chapter}

      Explain in 2-3 short paragraphs:
      1. WHY the correct answer is right (the key concept)
      2. What common misconception might lead a student to get this wrong
      3. A quick memory tip or analogy to remember it

      Keep it conversational and encouraging. Use simple language. Do not repeat the question.
      """

      case ai_client().call(@system_prompt, prompt, @llm_opts) do
        {:ok, text} when is_binary(text) ->
          {:ok, String.trim(text)}

        {:error, reason} ->
          Logger.warning("[StudyGuideAI] Failed to generate explanation: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Generates a concise concept summary for a chapter based on the
  student's weak areas.

  Returns `{:ok, summary_text}` or `{:error, reason}`.
  """
  def chapter_summary(chapter_name, wrong_questions, opts \\ []) do
    subject = opts[:subject] || "the subject"

    if mock_mode?() do
      {:ok, mock_chapter_summary(chapter_name, wrong_questions)}
    else
      questions_context =
        wrong_questions
        |> Enum.take(5)
        |> Enum.map_join("\n", fn q -> "- #{q["content"]}" end)

      prompt = """
      You are a #{subject} tutor. A student is struggling with "#{chapter_name}".

      Here are questions they got wrong:
      #{questions_context}

      Write a concise study summary (3-5 short paragraphs) covering:
      1. The key concepts in this chapter they need to understand
      2. How these concepts connect to each other
      3. Common pitfalls to avoid

      Be clear, use simple language, and include 1-2 concrete examples.
      Do NOT list the questions back. Focus on teaching the concepts.
      """

      case ai_client().call(@system_prompt, prompt, @llm_opts) do
        {:ok, text} when is_binary(text) ->
          {:ok, String.trim(text)}

        {:error, reason} ->
          Logger.warning("[StudyGuideAI] Failed to generate chapter summary: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # --- Mock content for development ---

  defp mock_explanation(_question, correct_answer, chapter) do
    """
    The correct answer is **#{correct_answer}**. This is a key concept in #{chapter} \
    that many students find tricky at first.

    A common mistake is confusing this with a related but different concept. \
    The key distinction is understanding the underlying mechanism — once you \
    see how it works, the answer becomes intuitive.

    **Memory tip:** Try to connect this concept to something you already know. \
    Think of it like a chain reaction — each step leads naturally to the next. \
    Review the relevant section in your materials and try explaining it in your own words.
    """
  end

  defp ai_client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)

  defp mock_chapter_summary(chapter_name, wrong_questions) do
    question_count = length(wrong_questions)

    """
    **#{chapter_name}** covers several interconnected concepts that build on each other. \
    Based on your practice results, there are #{question_count} areas that need attention.

    The foundation of this chapter is understanding the core principles and how they \
    apply in different scenarios. Many students struggle because they memorize facts \
    without understanding the "why" behind them.

    Focus on understanding the relationships between concepts rather than memorizing \
    individual facts. Try drawing a concept map connecting the key ideas, and practice \
    explaining each connection out loud. This active recall technique is much more \
    effective than re-reading your notes.
    """
  end
end
