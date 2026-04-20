defmodule FunSheep.Questions.QuestionFigure do
  @moduledoc """
  Join table associating a question with one or more source figures.

  A question may reference multiple figures (e.g., a question comparing
  two tables), and a figure may be referenced by multiple questions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "question_figures" do
    belongs_to :question, FunSheep.Questions.Question, primary_key: true
    belongs_to :source_figure, FunSheep.Content.SourceFigure, primary_key: true
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(qf, attrs) do
    qf
    |> cast(attrs, [:question_id, :source_figure_id, :position])
    |> validate_required([:question_id, :source_figure_id])
    |> unique_constraint([:question_id, :source_figure_id])
  end
end
