defmodule FunSheep.Questions.QuestionFlag do
  @moduledoc """
  Records a student's flag on a question — one flag per user per question.

  The reason is optional. Flagging without a reason still counts against
  the quality score (weight 5×). Providing a reason gives the course creator
  actionable information about what to fix.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @reasons [:incorrect_answer, :unclear, :outdated, :inappropriate]

  schema "question_flags" do
    field :reason, Ecto.Enum, values: @reasons

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :question, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  def reasons, do: @reasons

  @doc false
  def changeset(flag, attrs) do
    flag
    |> cast(attrs, [:reason, :user_role_id, :question_id])
    |> validate_required([:user_role_id, :question_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:question_id)
    |> unique_constraint([:user_role_id, :question_id],
      name: :question_flags_user_role_id_question_id_index,
      message: "already flagged this question"
    )
  end
end
