defmodule FunSheep.Resources do
  @moduledoc """
  The Resources context.

  Manages study reference resources tied to course sections, such as video
  links (YouTube, Khan Academy, etc.) that supplement student practice.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Resources.VideoResource

  ## Video Resources

  @doc """
  Lists all video resources for a given section, ordered by insertion time.
  """
  def list_videos_for_section(section_id) do
    VideoResource
    |> where([v], v.section_id == ^section_id)
    |> order_by([v], v.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all video resources for a given course, preloading the associated
  section. Results are ordered by section then insertion time.
  """
  def list_videos_for_course(course_id) do
    VideoResource
    |> where([v], v.course_id == ^course_id)
    |> order_by([v], [v.section_id, v.inserted_at])
    |> preload(:section)
    |> Repo.all()
  end

  @doc """
  Gets a single video resource by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_video_resource!(id), do: Repo.get!(VideoResource, id)

  @doc """
  Creates a video resource.

  Returns `{:ok, %VideoResource{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def create_video_resource(attrs) do
    %VideoResource{}
    |> VideoResource.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a video resource.

  Returns `{:ok, %VideoResource{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def update_video_resource(%VideoResource{} = video, attrs) do
    video
    |> VideoResource.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a video resource.

  Returns `{:ok, %VideoResource{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def delete_video_resource(%VideoResource{} = video) do
    Repo.delete(video)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking video resource changes.
  """
  def change_video_resource(%VideoResource{} = video, attrs \\ %{}) do
    VideoResource.changeset(video, attrs)
  end
end
