defmodule StudySmart.Accounts.UserRole do
  @moduledoc """
  Schema for user roles in StudySmart.

  Each record maps an Interactor Account Server user to a role
  (student, parent, or teacher) within the application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_roles" do
    field :interactor_user_id, :string
    field :role, Ecto.Enum, values: [:student, :parent, :teacher]
    field :email, :string
    field :display_name, :string
    field :grade, :string
    field :gender, :string
    field :nationality, :string
    field :metadata, :map, default: %{}

    belongs_to :school, StudySmart.Geo.School

    has_many :student_guardians, StudySmart.Accounts.StudentGuardian, foreign_key: :guardian_id

    has_many :student_guardian_links, StudySmart.Accounts.StudentGuardian,
      foreign_key: :student_id

    has_many :question_attempts, StudySmart.Questions.QuestionAttempt
    has_many :test_schedules, StudySmart.Assessments.TestSchedule
    has_many :uploaded_materials, StudySmart.Content.UploadedMaterial

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
      :nationality,
      :metadata,
      :school_id
    ])
    |> validate_required([:interactor_user_id, :role, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:interactor_user_id)
    |> foreign_key_constraint(:school_id)
  end
end
