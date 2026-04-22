defmodule FunSheep.AIUsageTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.AIUsage
  alias FunSheep.AIUsage.{Call, Tokenizer}

  describe "Tokenizer.count/1" do
    test "returns 0 for nil or empty" do
      assert Tokenizer.count(nil) == 0
      assert Tokenizer.count("") == 0
    end

    test "rounds up for short strings" do
      # chars_per_token = 4, so "a" (1 char) rounds up to 1 token
      assert Tokenizer.count("a") == 1
      assert Tokenizer.count("abcd") == 1
      assert Tokenizer.count("abcde") == 2
    end

    test "scales roughly linearly" do
      text = String.duplicate("hello world ", 100)
      count = Tokenizer.count(text)
      # 1200 chars / 4 ≈ 300 tokens
      assert count == 300
    end

    test "counts Unicode graphemes, not bytes" do
      # Each emoji is 1 grapheme but 4 bytes; heuristic operates on graphemes.
      assert Tokenizer.count("👋👋👋👋") == 1
    end
  end

  describe "log_call/1 with exact counts" do
    test "persists a row with interactor token_source when both counts given" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          model: "gpt-4o-mini",
          assistant_name: "question_gen",
          source: "ai_question_generation_worker",
          prompt_tokens: 123,
          completion_tokens: 45,
          duration_ms: 1842,
          status: "ok",
          metadata: %{course_id: "c_abc"}
        })

      assert call.provider == "interactor"
      assert call.model == "gpt-4o-mini"
      assert call.assistant_name == "question_gen"
      assert call.source == "ai_question_generation_worker"
      assert call.prompt_tokens == 123
      assert call.completion_tokens == 45
      assert call.total_tokens == 168
      assert call.token_source == "interactor"
      assert call.duration_ms == 1842
      assert call.status == "ok"
      assert call.metadata == %{"course_id" => "c_abc"}
      assert call.env == "test"
    end

    test "estimates the half that is missing while still flagging interactor source" do
      response_text = String.duplicate("x", 100)

      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "tutor_session",
          prompt_tokens: 200,
          response: response_text,
          status: "ok"
        })

      # prompt_tokens is authoritative (200); completion estimated from 100 chars / 4 = 25
      assert call.prompt_tokens == 200
      assert call.completion_tokens == 25
      assert call.total_tokens == 225
      assert call.token_source == "interactor"
    end
  end

  describe "log_call/1 with estimated counts" do
    test "tokenizes prompt and response when no exact counts provided" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "study_guide_ai",
          prompt: String.duplicate("a", 400),
          response: String.duplicate("b", 200),
          status: "ok"
        })

      assert call.prompt_tokens == 100
      assert call.completion_tokens == 50
      assert call.total_tokens == 150
      assert call.token_source == "estimated"
    end
  end

  describe "log_call/1 with failures" do
    test "records timeout status" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "worker_x",
          prompt: "hi",
          status: "timeout",
          error: ":timeout",
          duration_ms: 60_000
        })

      assert call.status == "timeout"
      assert call.error == ":timeout"
      assert call.prompt_tokens == 1
      assert call.completion_tokens == 0
      assert call.total_tokens == 1
    end

    test "records error status with arbitrary error term" do
      {:ok, %Call{} = call} =
        AIUsage.log_call(%{
          provider: "interactor",
          source: "worker_x",
          prompt: "hi",
          status: "error",
          error: {:http_error, 500}
        })

      assert call.status == "error"
      assert call.error == "{:http_error, 500}"
    end
  end

  describe "log_call/1 validation" do
    test "returns error changeset for invalid provider" do
      assert {:error, %Ecto.Changeset{} = cs} =
               AIUsage.log_call(%{
                 provider: "bogus",
                 source: "x",
                 status: "ok"
               })

      assert "is invalid" in errors_on(cs).provider
    end

    test "returns error changeset for invalid status" do
      assert {:error, %Ecto.Changeset{} = cs} =
               AIUsage.log_call(%{
                 provider: "interactor",
                 source: "x",
                 status: "bogus"
               })

      assert "is invalid" in errors_on(cs).status
    end
  end
end
