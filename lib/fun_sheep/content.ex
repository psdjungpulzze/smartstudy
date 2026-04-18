defmodule FunSheep.Content do
  @moduledoc """
  The Content context.

  Handles uploaded materials and OCR processing results.
  Provides text chunks for AI agent question extraction.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Content.{UploadedMaterial, OcrPage}

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
end
