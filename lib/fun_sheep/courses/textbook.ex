defmodule FunSheep.Courses.Textbook do
  @moduledoc """
  Schema for textbooks that can be associated with courses.

  Textbooks are populated dynamically via OpenLibrary API searches
  and cached locally for future lookups.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "textbooks" do
    field :title, :string
    field :author, :string
    field :publisher, :string
    field :edition, :string
    field :isbn, :string
    field :cover_image_url, :string
    field :subject, :string
    field :grades, {:array, :string}, default: []
    field :openlibrary_key, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(textbook, attrs) do
    textbook
    |> cast(attrs, [
      :title,
      :author,
      :publisher,
      :edition,
      :isbn,
      :cover_image_url,
      :subject,
      :grades,
      :openlibrary_key
    ])
    |> validate_required([:title, :subject])
    |> unique_constraint(:isbn)
    |> unique_constraint(:openlibrary_key)
  end
end
