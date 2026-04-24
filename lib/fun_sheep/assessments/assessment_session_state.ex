defmodule FunSheep.Assessments.AssessmentSessionState do
  @moduledoc """
  Schema for persisted assessment session state.

  Survives server restarts, allowing students to resume where they left off
  even when the ETS cache (StateCache) has been cleared. The `engine_state`
  column stores the full engine map as JSONB and is rehydrated on reconnect.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "assessment_session_states" do
    field :user_role_id, :string
    field :schedule_id, :string
    field :engine_state, :map
    field :question_number, :integer, default: 0
    field :phase, :string
    field :selected_answer, :string
    field :assessment_complete, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :user_role_id,
      :schedule_id,
      :engine_state,
      :question_number,
      :phase,
      :selected_answer,
      :assessment_complete
    ])
    |> validate_required([:user_role_id, :schedule_id])
  end
end
