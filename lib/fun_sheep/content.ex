defmodule FunSheep.Content do
  @moduledoc """
  The Content context.

  Handles uploaded materials and OCR processing results.
  Provides text chunks for AI agent question extraction.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Content.{UploadedMaterial, OcrPage, DiscoveredSource}

  ## Uploaded Materials

  def list_uploaded_materials do
    Repo.all(UploadedMaterial)
  end

  def list_materials_by_user(user_role_id) do
    from(m in UploadedMaterial,
      where: m.user_role_id == ^user_role_id,
      order_by: [desc: m.inserted_at]
    )
    |> Repo.all()
  end

  def list_materials_by_course(course_id) do
    from(m in UploadedMaterial, where: m.course_id == ^course_id)
    |> Repo.all()
  end

  @doc """
  Lists materials for a course uploaded by a specific user.
  Raw files are user-private; extracted content (chapters, questions) stays shared.
  """
  def list_materials_by_course_for_user(course_id, user_role_id) do
    from(m in UploadedMaterial,
      where: m.course_id == ^course_id and m.user_role_id == ^user_role_id,
      order_by: [asc: m.folder_name, asc: m.file_name]
    )
    |> Repo.all()
  end

  @doc """
  Lists unlinked materials (no course_id) for a user.
  These are staged uploads not yet processed.
  """
  def list_unlinked_materials_for_user(user_role_id) do
    from(m in UploadedMaterial,
      where: m.user_role_id == ^user_role_id and is_nil(m.course_id),
      order_by: [asc: m.folder_name, asc: m.file_name]
    )
    |> Repo.all()
  end

  def list_materials_by_batch(batch_id) do
    from(m in UploadedMaterial,
      where: m.batch_id == ^batch_id,
      order_by: [asc: m.folder_name, asc: m.file_name]
    )
    |> Repo.all()
  end

  def count_materials_by_batch(batch_id) do
    from(m in UploadedMaterial, where: m.batch_id == ^batch_id, select: count())
    |> Repo.one()
  end

  def get_course_id_for_batch(batch_id) do
    from(m in UploadedMaterial,
      where: m.batch_id == ^batch_id and not is_nil(m.course_id),
      select: m.course_id,
      limit: 1
    )
    |> Repo.one()
  end

  def link_batch_to_course(batch_id, course_id) do
    from(m in UploadedMaterial, where: m.batch_id == ^batch_id)
    |> Repo.update_all(set: [course_id: course_id])
  end

  @doc """
  Links all unlinked materials for a user to a course.
  Used when processing staged uploads.
  """
  def link_unlinked_materials_to_course(user_role_id, course_id) do
    from(m in UploadedMaterial,
      where: m.user_role_id == ^user_role_id and is_nil(m.course_id)
    )
    |> Repo.update_all(set: [course_id: course_id])
  end

  def delete_batch(batch_id) do
    delete_materials(list_materials_by_batch(batch_id))

    from(m in UploadedMaterial, where: m.batch_id == ^batch_id)
    |> Repo.delete_all()
  end

  def delete_batch_folder(batch_id, folder_name) do
    materials =
      from(m in UploadedMaterial,
        where: m.batch_id == ^batch_id and m.folder_name == ^folder_name
      )
      |> Repo.all()

    delete_materials(materials)

    from(m in UploadedMaterial,
      where: m.batch_id == ^batch_id and m.folder_name == ^folder_name
    )
    |> Repo.delete_all()
  end

  def delete_course_folder(course_id, folder_name) do
    materials =
      from(m in UploadedMaterial,
        where: m.course_id == ^course_id and m.folder_name == ^folder_name
      )
      |> Repo.all()

    delete_materials(materials)

    from(m in UploadedMaterial,
      where: m.course_id == ^course_id and m.folder_name == ^folder_name
    )
    |> Repo.delete_all()
  end

  defp delete_materials(materials) do
    uploads_dir = Application.app_dir(:fun_sheep, "priv/static")

    for mat <- materials do
      path = Path.join(uploads_dir, mat.file_path)
      File.rm(path)
    end
  end

  def get_uploaded_material!(id), do: Repo.get!(UploadedMaterial, id)

  def create_uploaded_material(attrs \\ %{}) do
    %UploadedMaterial{}
    |> UploadedMaterial.changeset(attrs)
    |> Repo.insert()
  end

  def update_uploaded_material(%UploadedMaterial{} = uploaded_material, attrs) do
    uploaded_material
    |> UploadedMaterial.changeset(attrs)
    |> Repo.update()
  end

  def delete_uploaded_material(%UploadedMaterial{} = uploaded_material) do
    delete_materials([uploaded_material])
    Repo.delete(uploaded_material)
  end

  def change_uploaded_material(%UploadedMaterial{} = uploaded_material, attrs \\ %{}) do
    UploadedMaterial.changeset(uploaded_material, attrs)
  end

  ## OCR Pages

  def list_ocr_pages do
    Repo.all(OcrPage)
  end

  def list_ocr_pages_by_material(material_id) do
    from(p in OcrPage,
      where: p.material_id == ^material_id,
      order_by: p.page_number
    )
    |> Repo.all()
  end

  def get_ocr_page!(id), do: Repo.get!(OcrPage, id)

  def create_ocr_page(attrs \\ %{}) do
    %OcrPage{}
    |> OcrPage.changeset(attrs)
    |> Repo.insert()
  end

  def update_ocr_page(%OcrPage{} = ocr_page, attrs) do
    ocr_page
    |> OcrPage.changeset(attrs)
    |> Repo.update()
  end

  def delete_ocr_page(%OcrPage{} = ocr_page) do
    Repo.delete(ocr_page)
  end

  def change_ocr_page(%OcrPage{} = ocr_page, attrs \\ %{}) do
    OcrPage.changeset(ocr_page, attrs)
  end

  ## Discovered Sources

  @doc """
  Lists all discovered sources for a course, ordered by confidence score.
  """
  def list_discovered_sources(course_id) do
    from(ds in DiscoveredSource,
      where: ds.course_id == ^course_id,
      order_by: [desc: ds.confidence_score, asc: ds.source_type]
    )
    |> Repo.all()
  end

  @doc """
  Lists discovered sources by type for a course.
  """
  def list_discovered_sources_by_type(course_id, source_type) do
    from(ds in DiscoveredSource,
      where: ds.course_id == ^course_id and ds.source_type == ^source_type,
      order_by: [desc: ds.confidence_score]
    )
    |> Repo.all()
  end

  @doc """
  Lists sources that are ready to be scraped (status = "discovered").
  """
  def list_scrapable_sources(course_id) do
    from(ds in DiscoveredSource,
      where: ds.course_id == ^course_id and ds.status == "discovered" and not is_nil(ds.url),
      order_by: [desc: ds.confidence_score]
    )
    |> Repo.all()
  end

  @doc """
  Gets summary stats for discovered sources.
  Returns %{total: N, by_type: %{"textbook" => N, ...}, questions: N}
  """
  def discovered_sources_summary(course_id) do
    sources = list_discovered_sources(course_id)

    %{
      total: length(sources),
      by_type: Enum.frequencies_by(sources, & &1.source_type),
      questions_extracted: sources |> Enum.map(& &1.questions_extracted) |> Enum.sum(),
      processed: Enum.count(sources, &(&1.status == "processed")),
      statuses: Enum.frequencies_by(sources, & &1.status)
    }
  end

  def get_discovered_source!(id), do: Repo.get!(DiscoveredSource, id)

  def create_discovered_source(attrs) do
    %DiscoveredSource{}
    |> DiscoveredSource.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a discovered source, ignoring duplicates (same course + URL).
  """
  def create_discovered_source_if_new(attrs) do
    %DiscoveredSource{}
    |> DiscoveredSource.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  def update_discovered_source(%DiscoveredSource{} = source, attrs) do
    source
    |> DiscoveredSource.changeset(attrs)
    |> Repo.update()
  end

  def delete_discovered_source(%DiscoveredSource{} = source) do
    Repo.delete(source)
  end
end
