defmodule FunSheep.Essays.EssayRubricTemplate do
  @moduledoc """
  Schema for essay rubric templates.

  Rubric templates define the scoring criteria for essay questions.
  Each template specifies:
  - The exam type it applies to (e.g. "ap_eng_lang", "gre_aw")
  - Criteria with individual max_points
  - A mastery_threshold_ratio for computing is_correct

  IMPORTANT: The bundled templates are generic PRACTICE rubrics, not official
  scoring guides. Official rubrics require admin-authored content.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "essay_rubric_templates" do
    field :name, :string
    field :exam_type, :string
    # List of %{"name" => ..., "max_points" => ..., "description" => ...}
    field :criteria, {:array, :map}
    field :max_score, :integer
    field :mastery_threshold_ratio, :float
    field :time_limit_minutes, :integer
    field :word_target, :integer
    field :word_limit, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name,
      :exam_type,
      :criteria,
      :max_score,
      :mastery_threshold_ratio,
      :time_limit_minutes,
      :word_target,
      :word_limit
    ])
    |> validate_required([:name, :exam_type, :criteria, :max_score, :mastery_threshold_ratio])
    |> validate_number(:max_score, greater_than: 0)
    |> validate_number(:mastery_threshold_ratio,
      greater_than: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> unique_constraint(:exam_type)
  end
end
