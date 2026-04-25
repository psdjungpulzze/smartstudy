defmodule FunSheep.Resources.VideoResource do
  @moduledoc """
  Schema for video resources linked to a course section.

  Stores instructor-curated or admin-added video links (YouTube, Khan Academy,
  or other sources) that students can reference while studying a section.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "video_resources" do
    field :title, :string
    field :url, :string
    field :source, Ecto.Enum, values: [:youtube, :khan_academy, :other]
    field :thumbnail_url, :string
    field :duration_seconds, :integer

    belongs_to :section, FunSheep.Courses.Section
    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :title,
      :url,
      :source,
      :thumbnail_url,
      :duration_seconds,
      :section_id,
      :course_id
    ])
    |> validate_required([:title, :url, :source, :section_id, :course_id])
    |> validate_length(:title, max: 255)
    |> validate_url_format(:url)
    |> foreign_key_constraint(:section_id)
    |> foreign_key_constraint(:course_id)
  end

  defp validate_url_format(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme} when scheme in ["http", "https"] -> []
        _ -> [{field, "must be a valid HTTP/HTTPS URL"}]
      end
    end)
  end
end
