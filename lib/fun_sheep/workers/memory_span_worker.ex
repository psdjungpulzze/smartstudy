defmodule FunSheep.Workers.MemorySpanWorker do
  @moduledoc """
  Oban worker that recalculates memory spans after a practice session.

  Triggered after any session where the student answers questions.
  Recalculates question → chapter → course span cascade for the given
  user and question set.

  Args:
    - `user_role_id` — the student's UserRole UUID
    - `question_ids` — list of question UUIDs answered in the session
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias FunSheep.MemorySpan

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_role_id" => user_role_id, "question_ids" => question_ids}}) do
    MemorySpan.recalculate_for_questions(user_role_id, question_ids)
  end
end
