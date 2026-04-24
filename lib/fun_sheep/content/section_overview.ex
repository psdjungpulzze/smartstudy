defmodule FunSheep.Content.SectionOverview do
  @moduledoc """
  Cached AI-generated concept overview for a section, per student.

  Generated on demand when a student visits the Study Hub for a section.
  Re-generated when stale (TTL controlled by `StudyHubLive`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "section_overviews" do
    field :body, :string
    field :generated_at, :utc_datetime

    belongs_to :section, FunSheep.Courses.Section
    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  def changeset(overview, attrs) do
    overview
    |> cast(attrs, [:body, :generated_at, :section_id, :user_role_id])
    |> validate_required([:body, :generated_at, :section_id, :user_role_id])
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:user_role_id)
  end
end
