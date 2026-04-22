defmodule FunSheep.Tutor do
  @moduledoc """
  AI Tutor context — manages Interactor AI agent sessions for student Q&A.

  The tutor acts as a subject-matter expert sitting next to the student,
  helping them understand questions they're working on. It uses:
  - UKB (User Knowledge Base) for course/curriculum content
  - UDB (User Database) for student performance history
  - Interactor Profiles for student preferences
  - Question + course context for focused answers
  """

  alias FunSheep.Interactor.{Agents, KnowledgeBase, Profiles}
  alias FunSheep.{Questions, Courses, Learning}
  alias FunSheep.Tutor.Session

  require Logger

  @assistant_name "funsheep_tutor"

  @system_prompt """
  You are a friendly, patient, and encouraging subject tutor helping a student \
  study for their exams. You are like a knowledgeable teacher sitting right next \
  to the student as they practice questions.

  ## Your Role
  - Help students UNDERSTAND concepts, don't just give answers
  - Use the Socratic method when appropriate — guide them to discover the answer
  - Explain WHY an answer is correct or incorrect
  - Relate concepts to things the student already knows
  - Be encouraging but honest about mistakes
  - Keep explanations concise and age-appropriate

  ## Rules
  - NEVER answer questions unrelated to the student's coursework
  - If asked about non-academic topics, politely redirect to studying
  - When giving hints, start with subtle hints before more obvious ones
  - Use simple language appropriate for the student's grade level
  - If the question has options, reference them by letter (A, B, C, D)
  - Always explain the underlying concept, not just the mechanics

  ## Personalization with Hobbies
  When the context lists the student's hobbies/interests, WEAVE THEM into
  analogies and examples. If they like KPOP/BTS, frame percentage problems
  around follower counts or chart positions. If they like soccer, use
  player stats. Use a hobby framing only where it actually illuminates
  the concept — forced references are worse than none. If no hobbies are
  listed, use plain examples.

  ## Weak Skills
  When the context lists weak skills, be patient on those topics and
  connect the current question to the broader skill if relevant. Never
  call the student "weak" or imply judgment — just acknowledge it's an
  area they're building up.

  ## Context
  You will receive context about:
  - The current question the student is working on
  - The course and chapter they're studying
  - Their past performance on similar questions
  - Their grade level and learning preferences

  Use this context to tailor your explanations.
  """

  @doc """
  Returns the assistant configuration for the tutor.
  The assistant is created on first use and the ID is cached in the application env.
  """
  def assistant_attrs do
    %{
      name: @assistant_name,
      description: "Student question tutor — helps understand coursework during practice",
      system_prompt: @system_prompt,
      llm_provider: "openai",
      llm_model: "gpt-4o",
      llm_config: %{temperature: 0.7, max_tokens: 1000},
      builtin_tools: %{profile_management: true},
      metadata: %{app: "funsheep", role: "tutor"}
    }
  end

  @doc """
  Ensures the tutor assistant exists in Interactor and returns its ID.
  Caches the ID in persistent_term for fast subsequent lookups.
  """
  def ensure_assistant do
    case :persistent_term.get({__MODULE__, :assistant_id}, nil) do
      nil ->
        case Agents.create_assistant(assistant_attrs()) do
          {:ok, %{"data" => %{"id" => id}}} ->
            :persistent_term.put({__MODULE__, :assistant_id}, id)
            {:ok, id}

          {:error, reason} ->
            Logger.error("Failed to create tutor assistant: #{inspect(reason)}")
            {:error, reason}
        end

      id ->
        {:ok, id}
    end
  end

  @doc """
  Starts a tutor session for the given student and question.

  Returns `{:ok, session_id}` where session_id can be used to send messages.
  The session is a GenServer that manages the Interactor room and
  broadcasts responses via PubSub.
  """
  def start_session(user_role_id, question_id, course_id) do
    with {:ok, assistant_id} <- ensure_assistant(),
         question <- Questions.get_question_with_context!(question_id),
         course <- Courses.get_course_with_chapters!(course_id),
         context <- build_context(question, course, user_role_id) do
      session_id = "tutor:#{user_role_id}:#{question_id}"

      case Session.start(session_id, %{
             assistant_id: assistant_id,
             external_user_id: user_role_id,
             question: question,
             course: course,
             context: context
           }) do
        {:ok, _pid} -> {:ok, session_id}
        {:error, {:already_started, _pid}} -> {:ok, session_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Sends a message to an active tutor session.
  The response is broadcast via PubSub to the session's topic.
  """
  def ask(session_id, message, opts \\ %{}) do
    Session.send_message(session_id, message, opts)
  end

  @doc """
  Sends a quick-action message (pre-built prompts for common requests).
  """
  def quick_action(session_id, action, question) do
    message =
      case action do
        "hint" ->
          "Give me a hint for this question without revealing the answer."

        "explain" ->
          "Explain the concept behind this question. What topic does it cover and what do I need to understand?"

        "why_wrong" ->
          "I got this question wrong. Explain why my answer was incorrect and help me understand the right answer."

        "step_by_step" ->
          "Walk me through how to solve this question step by step."

        "similar" ->
          "Can you give me a similar practice question to test my understanding?"

        _ ->
          message = action
          message
      end

    ask(session_id, message, %{
      metadata: %{
        action: action,
        question_id: question.id,
        question_content: question.content
      }
    })
  end

  @doc """
  Stops an active tutor session.
  """
  def stop_session(session_id) do
    Session.stop(session_id)
  end

  @doc """
  Builds rich context about the question, course, and student for the AI agent.
  """
  def build_context(question, course, user_role_id) do
    # Get student's attempt history for this question
    attempts = Questions.list_attempts_for_question(user_role_id, question.id)

    # Get question stats (crowd-sourced difficulty)
    stats = Questions.get_question_stats(question.id)

    # Try to get student profile from Interactor
    profile =
      case Profiles.get_effective_profile(user_role_id) do
        {:ok, %{"data" => data}} -> data
        _ -> %{}
      end

    # Search UKB for related curriculum content
    kb_results =
      case KnowledgeBase.search(%{
             query: question.content,
             category: course.subject || course.name,
             limit: 3,
             external_user_id: user_role_id
           }) do
        {:ok, %{"data" => data}} -> data
        _ -> []
      end

    %{
      question: %{
        content: question.content,
        type: question.question_type,
        options: question.options,
        correct_answer: question.answer,
        difficulty: question.difficulty,
        chapter: if(question.chapter, do: question.chapter.name, else: nil),
        hobby_context: question.hobby_context
      },
      course: %{
        name: course.name,
        subject: Map.get(course, :subject, nil),
        grade: Map.get(course, :grade, nil)
      },
      student: %{
        previous_attempts:
          Enum.map(attempts, fn a ->
            %{
              answer: a.answer_given,
              correct: a.is_correct,
              time_seconds: a.time_taken_seconds
            }
          end),
        profile: profile,
        hobbies: Learning.hobby_names_for_user(user_role_id),
        weak_skills: weak_skill_names_for(user_role_id, course.id)
      },
      stats: %{
        total_attempts: if(stats, do: stats.total_attempts, else: 0),
        correct_rate:
          if(stats && stats.total_attempts > 0,
            do: Float.round(stats.correct_attempts / stats.total_attempts * 100, 1),
            else: nil
          ),
        avg_time: if(stats, do: stats.avg_time_seconds, else: nil)
      },
      related_content: kb_results
    }
  end

  @doc """
  Returns the PubSub topic for a tutor session.
  """
  def topic(session_id), do: "tutor:#{session_id}"

  defp weak_skill_names_for(user_role_id, course_id) do
    deficits = Questions.skill_deficits(user_role_id, course_id)

    section_ids =
      deficits
      |> Enum.filter(fn {_id, d} -> d.total >= 2 and d.deficit >= 0.4 end)
      |> Enum.map(fn {id, _} -> id end)

    if section_ids == [] do
      []
    else
      section_ids
      |> Enum.map(fn id ->
        case FunSheep.Repo.get(FunSheep.Courses.Section, id) do
          nil -> nil
          section -> section.name
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

end
