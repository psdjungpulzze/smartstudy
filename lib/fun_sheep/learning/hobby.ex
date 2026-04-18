defmodule FunSheep.Learning.Hobby do
  @moduledoc """
  Schema for hobbies used in question personalization.

  Hobbies are discovered based on demographics and used to generate
  personalized questions with relatable context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hobbies" do
    field :name, :string
    field :category, :string
    field :region_relevance, :map

    has_many :student_hobbies, FunSheep.Learning.StudentHobby

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(hobby, attrs) do
    hobby
    |> cast(attrs, [:name, :category, :region_relevance])
    |> validate_required([:name, :category])
    |> unique_constraint(:name)
  end
end
