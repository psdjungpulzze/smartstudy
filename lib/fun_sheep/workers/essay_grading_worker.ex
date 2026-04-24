defmodule FunSheep.Workers.EssayGradingWorker do
  @moduledoc """
  Oban worker that grades submitted essays using `EssayGrader`.

  On completion:
  1. Records a `QuestionAttempt` with the essay score and draft reference.
  2. Marks the draft as submitted via `Essays.submit_draft/1`.
  3. Broadcasts `{:essay_graded, result}` on `"essay_grading:<draft_id>"`.
  4. Awards XP if `is_correct`.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  require Logger

  alias FunSheep.{Essays, Questions, Gamification, Repo}
  alias FunSheep.Questions.EssayGrader

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "draft_id" => draft_id,
          "question_id" => question_id,
          "user_role_id" => user_role_id
        }
      }) do
    with {:ok, draft} <- fetch_draft(draft_id),
         {:ok, question} <- fetch_question(question_id),
         {:ok, result} <- EssayGrader.grade(question, draft.body),
         {:ok, _attempt} <- record_attempt(draft, question, user_role_id, result),
         {:ok, _draft} <- Essays.submit_draft(draft_id) do
      maybe_award_xp(user_role_id, result)

      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        "essay_grading:#{draft_id}",
        {:essay_graded, result}
      )

      :ok
    else
      {:error, :draft_not_found} ->
        Logger.error("[EssayGrading] Draft not found: #{draft_id}")
        {:cancel, "draft_not_found"}

      {:error, :question_not_found} ->
        Logger.error("[EssayGrading] Question not found: #{question_id}")
        {:cancel, "question_not_found"}

      {:error, reason} ->
        Logger.error("[EssayGrading] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Enqueues a grading job for the given draft.
  """
  def enqueue(draft_id, question_id, user_role_id) do
    %{
      draft_id: draft_id,
      question_id: question_id,
      user_role_id: user_role_id
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  ## Private

  defp fetch_draft(draft_id) do
    case Repo.get(FunSheep.Essays.EssayDraft, draft_id) do
      nil -> {:error, :draft_not_found}
      draft -> {:ok, draft}
    end
  end

  defp fetch_question(question_id) do
    question =
      FunSheep.Questions.Question
      |> Repo.get(question_id)
      |> case do
        nil ->
          nil

        q ->
          Repo.preload(q, :essay_rubric_template)
      end

    case question do
      nil -> {:error, :question_not_found}
      q -> {:ok, q}
    end
  end

  defp record_attempt(draft, question, user_role_id, result) do
    Questions.record_attempt_with_stats(%{
      user_role_id: user_role_id,
      question_id: question.id,
      answer_given: String.slice(draft.body, 0, 1000),
      is_correct: result.is_correct,
      essay_draft_id: draft.id,
      essay_word_count: draft.word_count
    })
  end

  defp maybe_award_xp(_user_role_id, %{is_correct: false}), do: :ok

  defp maybe_award_xp(user_role_id, %{is_correct: true}) do
    Gamification.award_xp(user_role_id, 15, "essay_correct")
  rescue
    e ->
      Logger.warning("[EssayGrading] XP award failed (non-fatal): #{inspect(e)}")
      :ok
  end
end
