defmodule FunSheep.Courses.CourseBundle do
  @moduledoc """
  Schema for course bundles.

  A bundle groups two or more courses together at a discounted price.
  Bundles are displayed on the paywall when a student views a course they
  don't yet have access to, giving them the option to buy the full bundle
  instead of a single course.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_bundles" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :currency, :string, default: "usd"
    field :course_ids, {:array, Ecto.UUID}
    field :is_active, :boolean, default: true
    field :catalog_test_type, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [
      :name,
      :description,
      :price_cents,
      :currency,
      :course_ids,
      :is_active,
      :catalog_test_type
    ])
    |> validate_required([:name, :price_cents, :course_ids])
    |> validate_number(:price_cents, greater_than: 0)
    |> validate_length(:course_ids, min: 2)
  end
end
