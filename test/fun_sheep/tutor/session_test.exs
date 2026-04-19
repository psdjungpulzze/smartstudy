defmodule FunSheep.Tutor.SessionTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Tutor.Session

  @registry FunSheep.Tutor.SessionRegistry

  defp session_opts(_session_id, overrides \\ %{}) do
    defaults = %{
      assistant_id: "mock_assistant_#{System.unique_integer([:positive])}",
      external_user_id: Ecto.UUID.generate(),
      question: nil,
      course: nil,
      context: %{
        question: %{
          content: "What is 2 + 2?",
          type: :multiple_choice,
          options: %{"A" => "3", "B" => "4", "C" => "5", "D" => "6"},
          correct_answer: "4",
          difficulty: :easy,
          chapter: "Arithmetic",
          hobby_context: nil
        },
        course: %{
          name: "Basic Math",
          subject: "Math",
          grade: "5"
        },
        student: %{
          previous_attempts: [],
          profile: %{}
        },
        stats: %{
          total_attempts: 0,
          correct_rate: nil,
          avg_time: nil
        },
        related_content: []
      }
    }

    Map.merge(defaults, overrides)
  end

  defp unique_session_id do
    "test_session:#{System.unique_integer([:positive])}"
  end

  describe "start/2" do
    test "starts a GenServer and registers it in the SessionRegistry" do
      session_id = unique_session_id()
      assert {:ok, pid} = Session.start(session_id, session_opts(session_id))
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify registration in the registry
      assert [{^pid, _}] = Registry.lookup(@registry, session_id)

      Session.stop(session_id)
    end

    test "returns {:error, {:already_started, pid}} for duplicate session_id" do
      session_id = unique_session_id()
      {:ok, pid} = Session.start(session_id, session_opts(session_id))

      assert {:error, {:already_started, ^pid}} =
               Session.start(session_id, session_opts(session_id))

      Session.stop(session_id)
    end
  end

  describe "send_message/3" do
    test "returns {:ok, response} with a string response in mock mode" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      assert {:ok, response} = Session.send_message(session_id, "Help me understand this")
      assert is_binary(response)
      assert String.length(response) > 0

      Session.stop(session_id)
    end

    test "returns a hint-related response for hint messages" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      assert {:ok, response} = Session.send_message(session_id, "Give me a hint please")
      assert String.contains?(response, "hint") or String.contains?(response, "Hint")

      Session.stop(session_id)
    end

    test "returns an explanation for explain messages" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      assert {:ok, response} = Session.send_message(session_id, "Please explain the concept")
      assert String.contains?(response, "Arithmetic")

      Session.stop(session_id)
    end

    test "returns step-by-step guidance for solve messages" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      assert {:ok, response} = Session.send_message(session_id, "Walk me through step by step")
      assert String.contains?(response, "step")

      Session.stop(session_id)
    end

    test "returns {:error, :session_not_found} for a non-existent session" do
      assert {:error, :session_not_found} =
               Session.send_message("nonexistent_session", "hello")
    end

    test "accumulates messages in session state" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      {:ok, _} = Session.send_message(session_id, "First question")
      {:ok, _} = Session.send_message(session_id, "Second question")

      # Session still works after multiple messages
      assert {:ok, _} = Session.send_message(session_id, "Third question")

      Session.stop(session_id)
    end
  end

  describe "stop/1" do
    test "stops the GenServer process" do
      session_id = unique_session_id()
      {:ok, pid} = Session.start(session_id, session_opts(session_id))

      assert :ok = Session.stop(session_id)

      # Give a moment for the process to terminate
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "unregisters from the SessionRegistry after stopping" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      Session.stop(session_id)
      Process.sleep(50)

      assert Registry.lookup(@registry, session_id) == []
    end

    test "returns :ok for a session that does not exist" do
      assert :ok = Session.stop("nonexistent_session_#{System.unique_integer()}")
    end

    test "subsequent sends return :session_not_found after stop" do
      session_id = unique_session_id()
      {:ok, _pid} = Session.start(session_id, session_opts(session_id))

      Session.stop(session_id)
      Process.sleep(50)

      assert {:error, :session_not_found} = Session.send_message(session_id, "hello")
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts {:tutor_response, response} on the session topic" do
      session_id = unique_session_id()
      topic = FunSheep.Tutor.topic(session_id)

      # Subscribe to the session topic
      Phoenix.PubSub.subscribe(FunSheep.PubSub, topic)

      {:ok, _pid} = Session.start(session_id, session_opts(session_id))
      {:ok, _response} = Session.send_message(session_id, "Help me")

      assert_receive {:tutor_response, response}, 5_000
      assert is_binary(response)

      Session.stop(session_id)
    end
  end
end
