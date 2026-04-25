defmodule FunSheep.Accounts.UserRole do
  @moduledoc """
  Schema for user roles in FunSheep.

  Each record maps an Interactor Account Server user to a role
  (student, parent, or teacher) within the application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_roles" do
    field :interactor_user_id, :string
    field :role, Ecto.Enum, values: [:student, :parent, :teacher, :admin]
    field :email, :string
    field :display_name, :string
    field :grade, :string
    field :gender, :string
    field :ethnicity, :string
    field :metadata, :map, default: %{}
    field :suspended_at, :utc_datetime
    field :last_login_at, :utc_datetime
    field :timezone, :string
    field :onboarding_completed_at, :utc_datetime

    # Parent notification preferences (spec §8.1 / §8.2).
    field :digest_frequency, Ecto.Enum, values: [:weekly, :off], default: :weekly
    field :alerts_skipped_days, :boolean, default: false
    field :alerts_readiness_drop, :boolean, default: false
    field :alerts_goal_achieved, :boolean, default: true

    # Extended notification preferences (Phase 1 — alerts system).
    field :push_enabled, :boolean, default: true

    field :notification_frequency, Ecto.Enum,
      values: [:off, :light, :standard, :all],
      default: :standard

    field :notification_quiet_start, :integer, default: 21
    field :notification_quiet_end, :integer, default: 8

    # Per-type alert opt-outs.
    field :alerts_streak, :boolean, default: true
    field :alerts_friend_activity, :boolean, default: true
    field :alerts_test_upcoming, :boolean, default: true
    field :alerts_student_at_risk, :boolean, default: true
    field :alerts_class_digest, :boolean, default: true

    belongs_to :school, FunSheep.Geo.School
    belongs_to :pinned_test_schedule, FunSheep.Assessments.TestSchedule

    has_many :student_guardians, FunSheep.Accounts.StudentGuardian, foreign_key: :guardian_id

    has_many :student_guardian_links, FunSheep.Accounts.StudentGuardian, foreign_key: :student_id

    has_many :question_attempts, FunSheep.Questions.QuestionAttempt
    has_many :test_schedules, FunSheep.Assessments.TestSchedule
    has_many :uploaded_materials, FunSheep.Content.UploadedMaterial

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_role, attrs) do
    user_role
    |> cast(attrs, [
      :interactor_user_id,
      :role,
      :email,
      :display_name,
      :grade,
      :gender,
      :ethnicity,
      :metadata,
      :school_id,
      :suspended_at,
      :last_login_at,
      :timezone,
      :onboarding_completed_at,
      :digest_frequency,
      :alerts_skipped_days,
      :alerts_readiness_drop,
      :alerts_goal_achieved,
      :push_enabled,
      :notification_frequency,
      :notification_quiet_start,
      :notification_quiet_end,
      :alerts_streak,
      :alerts_friend_activity,
      :alerts_test_upcoming,
      :alerts_student_at_risk,
      :alerts_class_digest,
      :pinned_test_schedule_id
    ])
    |> validate_required([:interactor_user_id, :role, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint([:interactor_user_id, :role],
      name: :user_roles_interactor_user_id_role_index,
      message: "already has this role"
    )
    |> foreign_key_constraint(:school_id)
    |> foreign_key_constraint(:pinned_test_schedule_id)
  end

  @doc "Returns true if the account has been suspended."
  def suspended?(%__MODULE__{suspended_at: ts}), do: not is_nil(ts)
end
