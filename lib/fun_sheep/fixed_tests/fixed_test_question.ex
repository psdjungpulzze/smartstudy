defmodule FunSheep.FixedTests.FixedTestQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(multiple_choice short_answer true_false)

  schema "fixed_test_questions" do
    field :position, :integer
    field :question_text, :string
    field :answer_text, :string
    field :question_type, :string, default: "multiple_choice"
    field :options, :map
    field :explanation, :string
    field :points, :integer, default: 1
    field :image_url, :string

    belongs_to :bank, FunSheep.FixedTests.FixedTestBank

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :bank_id,
      :position,
      :question_text,
      :answer_text,
      :question_type,
      :options,
      :explanation,
      :points,
      :image_url
    ])
    |> validate_required([:bank_id, :position, :question_text, :answer_text])
    |> validate_inclusion(:question_type, @valid_types)
    |> validate_number(:points, greater_than: 0)
    |> validate_number(:position, greater_than: 0)
    |> validate_length(:question_text, min: 1)
    |> validate_length(:answer_text, min: 1)
  end
end
