defmodule FunSheepWeb.UploadController do
  use FunSheepWeb, :controller

  alias FunSheep.Content

  def create(conn, %{"file" => upload, "batch_id" => batch_id} = params) do
    user_role_id = params["user_role_id"]
    folder_name = params["folder_name"]

    unless user_role_id do
      conn |> put_status(401) |> json(%{error: "unauthorized"}) |> halt()
    end

    basename = Path.basename(upload.filename)

    sub_dir =
      if folder_name && folder_name != "",
        do: Path.join(["uploads", "staging", batch_id, folder_name]),
        else: Path.join(["uploads", "staging", batch_id])

    uploads_dir = Application.app_dir(:fun_sheep, "priv/static")
    dest_dir = Path.join(uploads_dir, sub_dir)

    try do
      File.mkdir_p!(dest_dir)
      dest = Path.join(dest_dir, basename)
      File.cp!(upload.path, dest)

      # Check if this batch is already linked to a course
      course_id = Content.get_course_id_for_batch(batch_id)

      case Content.create_uploaded_material(%{
             file_name: basename,
             file_path: "/#{sub_dir}/#{basename}",
             file_type: upload.content_type,
             file_size: get_file_size(upload.path),
             folder_name: folder_name,
             batch_id: batch_id,
             user_role_id: user_role_id,
             course_id: course_id
           }) do
        {:ok, material} ->
          json(conn, %{id: material.id, file_name: material.file_name})

        {:error, changeset} ->
          conn
          |> put_status(422)
          |> json(%{error: "Failed to save", details: inspect(changeset.errors)})
      end
    rescue
      e ->
        conn
        |> put_status(500)
        |> json(%{error: "Upload failed", details: Exception.message(e)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing file, batch_id, or user_role_id"})
  end

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
