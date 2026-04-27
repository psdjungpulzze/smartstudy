defmodule FunSheep.Tutor.Session do
  @moduledoc """
  GenServer managing a single AI tutor conversation session.

  Each session corresponds to one Interactor room. It:
  - Creates the room on start
  - Sends messages with enriched context
  - Polls/streams responses from the Interactor agent
  - Broadcasts responses via PubSub for the LiveView to consume

  In mock mode, simulates AI responses locally.
  """

  use GenServer, restart: :temporary

  alias FunSheep.Interactor.Agents

  require Logger

  @registry FunSheep.Tutor.SessionRegistry
  @pubsub FunSheep.PubSub
  @idle_timeout :timer.minutes(30)

  # --- Public API ---

  def start(session_id, opts) do
    GenServer.start_link(__MODULE__, Map.put(opts, :session_id, session_id),
      name: via(session_id)
    )
  end

  def send_message(session_id, content, opts \\ %{}) do
    GenServer.call(via(session_id), {:send_message, content, opts}, 30_000)
  catch
    :exit, {:noproc, _} -> {:error, :session_not_found}
  end

  def stop(session_id) do
    GenServer.stop(via(session_id), :normal)
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp via(session_id), do: {:via, Horde.Registry, {@registry, session_id}}

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    %{
      session_id: session_id,
      assistant_id: assistant_id,
      external_user_id: external_user_id,
      context: context
    } = opts

    # Create a room in Interactor for this session
    room_metadata = %{
      app: "funsheep",
      purpose: "tutor",
      question_content: get_in(context, [:question, :content]),
      chapter: get_in(context, [:question, :chapter]),
      course_name: get_in(context, [:course, :name])
    }

    room_id =
      case Agents.create_room(assistant_id, external_user_id, room_metadata) do
        {:ok, %{"data" => %{"id" => id}}} -> id
        _ -> "mock_room_#{session_id}"
      end

    state = %{
      session_id: session_id,
      room_id: room_id,
      assistant_id: assistant_id,
      external_user_id: external_user_id,
      context: context,
      messages: [],
      idle_timer: schedule_idle_timeout()
    }

    # Send an initial context message to prime the assistant
    prime_message = build_prime_message(context)
    do_send_message(state, prime_message, %{role: "system"})

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, content, opts}, _from, state) do
    # Cancel and reschedule idle timer
    Process.cancel_timer(state.idle_timer)

    # Enrich message with current question context
    enriched_content = enrich_message(content, state.context)

    case do_send_message(state, enriched_content, opts) do
      {:ok, response} ->
        message = %{role: "user", content: content, timestamp: DateTime.utc_now()}
        assistant_msg = %{role: "assistant", content: response, timestamp: DateTime.utc_now()}

        new_state = %{
          state
          | messages: state.messages ++ [message, assistant_msg],
            idle_timer: schedule_idle_timeout()
        }

        # Broadcast the response
        Phoenix.PubSub.broadcast(
          @pubsub,
          FunSheep.Tutor.topic(state.session_id),
          {:tutor_response, response}
        )

        {:reply, {:ok, response}, new_state}

      {:error, reason} ->
        new_state = %{state | idle_timer: schedule_idle_timeout()}
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    Logger.info("Tutor session #{state.session_id} idle timeout, stopping")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close the room in Interactor (best-effort)
    if not mock_mode?() do
      Agents.close_room(state.room_id)
    end

    :ok
  end

  # --- Private ---

  defp do_send_message(state, content, opts) do
    if mock_mode?() do
      mock_response(content, state.context)
    else
      message_params =
        Map.merge(
          %{
            content: content,
            external_user_id: state.external_user_id
          },
          opts
        )

      case Agents.send_message(state.room_id, content, message_params) do
        {:ok, %{"data" => %{"id" => msg_id}}} ->
          # Poll for the assistant's response
          poll_for_response(state.room_id, msg_id)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp poll_for_response(room_id, after_msg_id, attempts \\ 0) do
    if attempts >= 30 do
      {:error, :timeout}
    else
      Process.sleep(1_000)

      case Agents.list_messages(room_id) do
        {:ok, %{"data" => messages}} when is_list(messages) ->
          # Find the latest assistant message
          case Enum.find(Enum.reverse(messages), &(&1["role"] == "assistant")) do
            %{"content" => content} when content != nil and content != "" ->
              {:ok, content}

            _ ->
              poll_for_response(room_id, after_msg_id, attempts + 1)
          end

        _ ->
          poll_for_response(room_id, after_msg_id, attempts + 1)
      end
    end
  end

  defp mock_response(content, context) do
    # Simulate a brief delay
    Process.sleep(500)

    question = context[:question] || %{}
    question_content = question[:content] || "this question"
    correct_answer = question[:correct_answer] || "the correct answer"
    chapter = question[:chapter] || "this topic"

    response =
      cond do
        String.contains?(content, "hint") ->
          "Here's a hint: Think about what #{chapter} covers. " <>
            "Consider the key concepts and how they apply to this specific scenario. " <>
            "Try to eliminate the options that don't fit."

        String.contains?(content, "explain") or String.contains?(content, "concept") ->
          "This question is about **#{chapter}**. " <>
            "The key concept here is understanding how the fundamentals apply. " <>
            "Let me break it down: the question asks you to think about " <>
            "the relationship between the given information and the expected outcome. " <>
            "Focus on the core principles you've learned in this chapter."

        String.contains?(content, "wrong") or String.contains?(content, "incorrect") ->
          "The correct answer is **#{correct_answer}**. " <>
            "Let me explain why: this question tests your understanding of #{chapter}. " <>
            "A common mistake is to overlook the specific conditions stated in the question. " <>
            "Remember, the key is to carefully read what's being asked and apply the right concept."

        String.contains?(content, "step by step") or String.contains?(content, "solve") ->
          "Let's work through this step by step:\n\n" <>
            "1. First, read the question carefully: \"#{String.slice(question_content, 0..80)}...\"\n" <>
            "2. Identify what concept from #{chapter} applies here\n" <>
            "3. Consider each option and test it against the concept\n" <>
            "4. The answer that best fits the concept is the correct one\n\n" <>
            "Try applying these steps and see if you can arrive at the answer!"

        String.contains?(content, "similar") ->
          "Here's a similar practice question:\n\n" <>
            "Based on the same concepts from #{chapter}, " <>
            "try this: If we changed the conditions slightly, " <>
            "how would your approach change? Think about what stays the same " <>
            "and what would be different."

        true ->
          "Great question! Looking at \"#{String.slice(question_content, 0..60)}...\", " <>
            "this relates to #{chapter}. " <>
            "The key thing to understand is the underlying concept. " <>
            "Would you like me to give you a hint, explain the concept, " <>
            "or walk you through it step by step?"
      end

    {:ok, response}
  end

  defp build_prime_message(context) do
    question = context[:question] || %{}
    course = context[:course] || %{}
    student = context[:student] || %{}
    stats = context[:stats] || %{}

    options_text =
      case question[:options] do
        nil ->
          ""

        opts when is_map(opts) ->
          formatted =
            opts
            |> Enum.sort_by(fn {k, _} -> k end)
            |> Enum.map_join("\n", fn {k, v} -> "  #{k}. #{v}" end)

          "\nOptions:\n#{formatted}"

        _ ->
          ""
      end

    attempts_text =
      case student[:previous_attempts] do
        [] ->
          "This is the student's first attempt at this question."

        attempts when is_list(attempts) ->
          latest = List.last(attempts)

          "The student has attempted this #{length(attempts)} time(s). " <>
            "Latest attempt: answered \"#{latest[:answer]}\" " <>
            "(#{if latest[:correct], do: "correct", else: "incorrect"})."

        _ ->
          ""
      end

    stats_text =
      if stats[:total_attempts] && stats[:total_attempts] > 0 do
        "Community stats: #{stats[:correct_rate]}% of students answer correctly " <>
          "(#{stats[:total_attempts]} total attempts, avg #{stats[:avg_time]}s)."
      else
        ""
      end

    hobbies_text =
      case student[:hobbies] do
        list when is_list(list) and list != [] ->
          "Student's hobbies/interests (use for analogies when they illuminate " <>
            "the concept): " <> Enum.join(list, ", ") <> "."

        _ ->
          ""
      end

    weak_skills_text =
      case student[:weak_skills] do
        list when is_list(list) and list != [] ->
          "Skills the student is building up (be patient, reinforce gently): " <>
            Enum.join(list, ", ") <> "."

        _ ->
          ""
      end

    """
    [CONTEXT] The student is working on the following question:

    Course: #{course[:name]}#{if course[:grade], do: " (Grade #{course[:grade]})", else: ""}
    Chapter: #{question[:chapter] || "Unknown"}
    Difficulty: #{question[:difficulty] || "Unknown"}
    Question Type: #{question[:type]}

    Question: #{question[:content]}#{options_text}

    Correct Answer: #{question[:correct_answer]}

    #{attempts_text}
    #{stats_text}

    #{hobbies_text}
    #{weak_skills_text}

    #{if question[:hobby_context], do: "Question-specific hobby framing already applied: #{question[:hobby_context]}", else: ""}

    Help the student understand this question. Do NOT reveal the answer unless they explicitly ask for it or have already answered incorrectly.
    """
  end

  defp enrich_message(content, _context) do
    # The context is already primed in the room, so just pass through the user message
    content
  end

  defp schedule_idle_timeout do
    Process.send_after(self(), :idle_timeout, @idle_timeout)
  end

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)
end
