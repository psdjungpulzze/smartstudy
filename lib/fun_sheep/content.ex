defmodule FunSheep.Content do
  @moduledoc """
  The Content context.

  Handles uploaded materials and OCR processing results.
  Provides text chunks for AI agent question extraction.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Content.{UploadedMaterial, OcrPage, DiscoveredSource, SourceFigure}

  ## Uploaded Materials

  def list_uploaded_materials do
    Repo.all(UploadedMaterial)
  end

  @doc """
  Admin-facing paginated material list. Supports search on file_name and
  filter by ocr_status. Preloads course and uploader.
  """
  def list_materials_for_admin(opts \\ []) do
    opts
    |> admin_materials_query()
    |> order_by([m], desc: m.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 25))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload([:course, :user_role])
    |> Repo.all()
  end

  @doc "Counts materials matching the same filters used by `list_materials_for_admin/1`."
  def count_materials_for_admin(opts \\ []) do
    opts
    |> admin_materials_query()
    |> select([m], count(m.id))
    |> Repo.one()
  end

  defp admin_materials_query(opts) do
    search = Keyword.get(opts, :search)
    status = Keyword.get(opts, :status)
    query = from(m in UploadedMaterial)

    query =
      case status do
        nil -> query
        "" -> query
        s when is_binary(s) -> from(m in query, where: m.ocr_status == ^s)
      end

    case search do
      nil ->
        query

      "" ->
        query

      term when is_binary(term) ->
        pattern = "%#{term}%"
        from(m in query, where: ilike(m.file_name, ^pattern))
    end
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

  @doc """
  Lists materials for a course filtered to one or more material_kind values.
  Pass a single atom or a list of atoms.
  """
  def list_materials_by_course_and_kind(course_id, kinds) when is_list(kinds) do
    from(m in UploadedMaterial,
      where: m.course_id == ^course_id and m.material_kind in ^kinds,
      order_by: [asc: m.folder_name, asc: m.file_name]
    )
    |> Repo.all()
  end

  def list_materials_by_course_and_kind(course_id, kind) when is_atom(kind),
    do: list_materials_by_course_and_kind(course_id, [kind])

  @doc """
  Returns which material kinds the user has uploaded for this course.
  """
  def course_material_kinds(course_id) do
    from(m in UploadedMaterial,
      where: m.course_id == ^course_id,
      select: m.material_kind,
      distinct: true
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
    for mat <- materials do
      FunSheep.Storage.delete(mat.file_path)
    end
  end

  @doc """
  Resets failed AND partially-failed uploaded materials in a course back to
  `:pending` so OCR can be retried. Returns `{count, material_ids}` — the
  count and IDs of materials that were reset. Fully-completed materials are
  left alone so we don't redo work that already succeeded.
  """
  def reset_failed_materials(course_id) do
    query =
      from(m in UploadedMaterial,
        where: m.course_id == ^course_id and m.ocr_status in [:failed, :partial],
        select: m.id
      )

    {count, ids} =
      Repo.update_all(query, set: [ocr_status: :pending, ocr_error: nil])

    {count, ids}
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

  @doc """
  Atomically increments `ocr_pages_completed` for a material by `n`.

  Chunk pollers for a single PDF run concurrently; a `get → update` round-trip
  would race and lose increments. `UPDATE ... SET ocr_pages_completed =
  ocr_pages_completed + n` is serialized by Postgres row lock.

  Returns the new value of `ocr_pages_completed` after the increment, so
  callers can decide whether this increment was the one that tipped the
  material into `:completed`.
  """
  def increment_ocr_pages_completed(material_id, n) when is_integer(n) and n >= 0 do
    {1, [new_count]} =
      from(m in UploadedMaterial,
        where: m.id == ^material_id,
        select: m.ocr_pages_completed
      )
      |> Repo.update_all(inc: [ocr_pages_completed: n])

    new_count
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

  @doc """
  Inserts an OcrPage or updates the existing one for the same
  (material_id, page_number). Used by the PDF chunk poller: a chunk may
  be re-polled after a worker crash, and re-inserting would violate the
  unique index. Returns {:inserted | :updated, %OcrPage{}}.
  """
  def upsert_ocr_page(attrs) do
    changeset = OcrPage.changeset(%OcrPage{}, attrs)

    case Repo.insert(changeset,
           on_conflict:
             {:replace, [:extracted_text, :bounding_boxes, :images, :status, :error, :updated_at]},
           conflict_target: [:material_id, :page_number],
           returning: [:id, :inserted_at, :updated_at]
         ) do
      {:ok, %OcrPage{} = page} ->
        # When insert_at == updated_at (within 1 second) it's a fresh row.
        # We use this to tell the chunk poller whether to bump the counter.
        fresh? = DateTime.compare(page.inserted_at, page.updated_at) == :eq
        tag = if fresh?, do: :inserted, else: :updated
        {tag, page}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_ocr_page(%OcrPage{} = ocr_page, attrs) do
    ocr_page
    |> OcrPage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes all OCR pages for a material. Used by the OCR pipeline before a
  reprocess so we don't collide with the `(material_id, page_number)` unique
  constraint when retrying.
  """
  def delete_ocr_pages_for_material(material_id) do
    {count, _} =
      from(p in OcrPage, where: p.material_id == ^material_id)
      |> Repo.delete_all()

    count
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
  Video-type sources linked to a specific section (skill). Used by the
  practice UI on wrong-answer / "I don't know" events — North Star I-14.
  Returns `[]` when no videos are linked (honesty, I-16).
  """
  def list_videos_for_section(nil), do: []

  def list_videos_for_section(section_id) do
    from(ds in DiscoveredSource,
      where:
        ds.section_id == ^section_id and ds.source_type == "video" and
          not is_nil(ds.url),
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

  @doc """
  Resets all failed discovered sources back to "discovered" so they can be retried.
  Returns the number of sources reset.
  """
  def reset_failed_sources(course_id) do
    {count, _} =
      from(ds in DiscoveredSource,
        where: ds.course_id == ^course_id and ds.status == "failed"
      )
      |> Repo.update_all(set: [status: "discovered"])

    count
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

  ## Source Figures

  @doc """
  Creates a source figure record (extracted table/figure/graph from OCR).
  """
  def create_source_figure(attrs) do
    %SourceFigure{}
    |> SourceFigure.changeset(attrs)
    |> Repo.insert()
  end

  def get_source_figure!(id), do: Repo.get!(SourceFigure, id)

  def list_figures_by_material(material_id) do
    from(f in SourceFigure,
      where: f.material_id == ^material_id,
      order_by: [asc: f.page_number, asc: f.inserted_at]
    )
    |> Repo.all()
  end

  def list_figures_by_course(course_id) do
    from(f in SourceFigure,
      join: m in UploadedMaterial,
      on: f.material_id == m.id,
      where: m.course_id == ^course_id,
      order_by: [asc: f.page_number, asc: f.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Deletes all figures for a given ocr_page. Used when reprocessing a page.
  """
  def delete_figures_for_page(ocr_page_id) do
    from(f in SourceFigure, where: f.ocr_page_id == ^ocr_page_id)
    |> Repo.delete_all()
  end
end
