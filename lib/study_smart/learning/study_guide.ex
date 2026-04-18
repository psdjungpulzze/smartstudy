defmodule StudySmart.Learning.StudyGuide do
  @moduledoc """
  Schema for AI-generated study guides.

  Each guide contains structured content targeting weak topics
  with reference pages and recommendations, tied to a test schedule.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "study_guides" do
    field :content, :map
    field :generated_at, :utc_datetime

    belongs_to :user_role, StudySmart.Accounts.UserRole
    belongs_to :test_schedule, StudySmart.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(study_guide, attrs) do
    study_guide
    |> cast(attrs, [:content, :generated_at, :user_role_id, :test_schedule_id])
    |> validate_required([:content, :generated_at, :user_role_id, :test_schedule_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:test_schedule_id)
  end
end
