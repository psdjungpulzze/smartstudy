defmodule FunSheep.Workers.ExamTimeoutWorker do
  @moduledoc """
  Oban worker that auto-submits in-progress exam simulation sessions when
  their time limit expires. Acts as a fallback when the LiveView process
  has died (network drop, browser close).
  """

  use Oban.Worker, queue: :assessments, unique: [period: :infinity, keys: [:session_id]]

  alias FunSheep.Assessments.{ExamSimulationEngine, ExamSimulations}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    case ExamSimulations.get_session!(session_id) do
      %{status: "in_progress"} ->
        ExamSimulationEngine.timeout(session_id)
        :ok

      _ ->
        :ok
    end
  rescue
    Ecto.NoResultsError -> :ok
  end
end
