defmodule FunSheepWeb.UploadController do
  use FunSheepWeb, :controller

  alias FunSheep.Content
  alias FunSheep.Storage

  def create(conn, %{"file" => upload, "batch_id" => batch_id} = params) do
    user_role_id = params["user_role_id"]
    folder_name = params["folder_name"]
    material_kind = normalize_kind(params["material_kind"])

    unless user_role_id do
      conn |> put_status(401) |> json(%{error: "unauthorized"}) |> halt()
    end

    basename = Path.basename(upload.filename)
    key = build_key(batch_id, folder_name, basename)

    with {:ok, content} <- File.read(upload.path),
         {:ok, stored_key} <-
           Storage.put(key, content, content_type: upload.content_type),
         course_id = Content.get_course_id_for_batch(batch_id),
         {:ok, material} <-
           Content.create_uploaded_material(%{
             file_name: basename,
             file_path: stored_key,
             file_type: upload.content_type,
             file_size: byte_size(content),
             folder_name: folder_name,
             batch_id: batch_id,
             material_kind: material_kind,
             user_role_id: user_role_id,
             course_id: course_id
           }) do
      json(conn, %{
        id: material.id,
        file_name: material.file_name,
        material_kind: material.material_kind
      })
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: "Failed to save", details: inspect(changeset.errors)})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Upload failed", details: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing file, batch_id, or user_role_id"})
  end

  defp build_key(batch_id, folder_name, basename) when folder_name in [nil, ""] do
    Path.join(["staging", batch_id, basename])
  end

  defp build_key(batch_id, folder_name, basename) do
    Path.join(["staging", batch_id, folder_name, basename])
  end

  defp normalize_kind(nil), do: :textbook
  defp normalize_kind(""), do: :textbook

  defp normalize_kind(value) when is_binary(value) do
    allowed = FunSheep.Content.UploadedMaterial.material_kinds()
    atom = String.to_existing_atom(value)
    if atom in allowed, do: atom, else: :textbook
  rescue
    ArgumentError -> :textbook
  end

  defp normalize_kind(value) when is_atom(value) do
    if value in FunSheep.Content.UploadedMaterial.material_kinds(), do: value, else: :textbook
  end
end
