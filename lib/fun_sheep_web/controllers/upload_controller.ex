defmodule FunSheepWeb.UploadController do
  use FunSheepWeb, :controller

  alias FunSheep.Content
  alias FunSheep.Storage

  # ── Legacy small-file upload via multipart POST ──────────────────────────
  # Kept for backward compatibility with callers that can't do a direct GCS
  # PUT. Goes through the web container's memory — unsuitable for anything
  # larger than a few MB. New uploads should prefer `sign` + `finalize`.

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

  # ── Resumable direct-to-storage upload ───────────────────────────────────
  # The browser calls `sign` to get a one-shot upload URL it can PUT the file
  # to directly. For GCS this URL is a pre-authorized resumable session URI
  # scoped to a single object key; for the Local backend it's a dev-only
  # endpoint on this app. Either way the web container never reads the file
  # body — essential for 200–500 MB PDFs that would OOM `File.read!/1`.

  def sign(conn, %{"batch_id" => batch_id, "file_name" => file_name} = params) do
    user_role_id = params["user_role_id"] || params["user_role"] || get_user_role_id(conn)
    folder_name = params["folder_name"]
    content_type = params["file_type"] || "application/octet-stream"
    content_length = parse_length(params["file_size"])

    cond do
      user_role_id in [nil, ""] ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      !valid_batch_id?(batch_id) ->
        conn |> put_status(400) |> json(%{error: "invalid batch_id"})

      true ->
        basename = Path.basename(file_name)
        key = build_key(batch_id, folder_name, basename)

        opts =
          [content_type: content_type]
          |> maybe_put(:content_length, content_length)

        case Storage.start_resumable_upload(key, opts) do
          {:ok, %{upload_url: upload_url, object_key: object_key}} ->
            json(conn, %{
              upload_url: upload_url,
              object_key: object_key,
              # 7 days — GCS resumable sessions are valid for a week. Clients
              # that take longer than that to start PUT-ing have bigger
              # problems than URL expiry.
              expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_iso8601()
            })

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "Could not start upload", details: inspect(reason)})
        end
    end
  end

  def sign(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing batch_id or file_name"})
  end

  def finalize(conn, %{"object_key" => object_key, "batch_id" => batch_id} = params) do
    user_role_id = params["user_role_id"] || get_user_role_id(conn)
    folder_name = params["folder_name"]
    material_kind = normalize_kind(params["material_kind"])
    file_name = params["file_name"] || Path.basename(object_key)
    declared_type = params["file_type"] || "application/octet-stream"

    cond do
      user_role_id in [nil, ""] ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      !valid_batch_id?(batch_id) ->
        conn |> put_status(400) |> json(%{error: "invalid batch_id"})

      !object_under_batch?(object_key, batch_id) ->
        # Fail loud if the client is trying to finalize an object that
        # doesn't live under the batch prefix — that would let anyone
        # create material rows pointing at arbitrary GCS objects.
        conn |> put_status(400) |> json(%{error: "object_key outside batch prefix"})

      true ->
        case Storage.object_info(object_key) do
          {:ok, %{size: actual_size}} ->
            course_id = Content.get_course_id_for_batch(batch_id)

            attrs = %{
              file_name: file_name,
              file_path: object_key,
              file_type: declared_type,
              file_size: actual_size,
              folder_name: folder_name,
              batch_id: batch_id,
              material_kind: material_kind,
              user_role_id: user_role_id,
              course_id: course_id
            }

            case Content.create_uploaded_material(attrs) do
              {:ok, material} ->
                json(conn, %{
                  id: material.id,
                  file_name: material.file_name,
                  material_kind: material.material_kind
                })

              {:error, %Ecto.Changeset{} = changeset} ->
                conn
                |> put_status(422)
                |> json(%{error: "Failed to save", details: inspect(changeset.errors)})
            end

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "object not found in storage"})

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "Storage check failed", details: inspect(reason)})
        end
    end
  end

  def finalize(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing object_key or batch_id"})
  end

  # ── Local-backend direct PUT receiver (dev/test only) ────────────────────
  # The Local storage backend returns a URL pointing here; the JS client
  # PUTs the file body to it as if talking to GCS. Rejected in prod because
  # the route is only mounted when storage_backend == Local.

  def local_put(conn, %{"token" => token, "key" => key_parts}) do
    key = Enum.join(key_parts, "/")

    cond do
      Application.get_env(:fun_sheep, :storage_backend) != FunSheep.Storage.Local ->
        conn |> put_status(404) |> json(%{error: "not found"})

      !FunSheep.Storage.Local.verify_token(key, token) ->
        conn |> put_status(403) |> json(%{error: "invalid token"})

      true ->
        {:ok, body, conn} = read_full_body(conn)

        content_type =
          conn
          |> get_req_header("content-type")
          |> List.first()
          |> Kernel.||("application/octet-stream")

        case FunSheep.Storage.Local.put(key, body, content_type: content_type) do
          {:ok, _} -> json(conn, %{status: "ok", object_key: key})
          {:error, reason} -> conn |> put_status(500) |> json(%{error: inspect(reason)})
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp read_full_body(conn) do
    read_full_body(conn, [])
  end

  defp read_full_body(conn, acc) do
    case Plug.Conn.read_body(conn, length: 8_000_000, read_length: 1_000_000) do
      {:ok, chunk, conn} -> {:ok, IO.iodata_to_binary([acc, chunk]), conn}
      {:more, chunk, conn} -> read_full_body(conn, [acc, chunk])
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_key(batch_id, folder_name, basename) when folder_name in [nil, ""] do
    Path.join(["staging", batch_id, basename])
  end

  defp build_key(batch_id, folder_name, basename) do
    Path.join(["staging", batch_id, folder_name, basename])
  end

  defp object_under_batch?(object_key, batch_id) do
    String.starts_with?(object_key, "staging/#{batch_id}/")
  end

  defp valid_batch_id?(batch_id) when is_binary(batch_id) do
    case Ecto.UUID.cast(batch_id) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp valid_batch_id?(_), do: false

  defp parse_length(nil), do: nil
  defp parse_length(n) when is_integer(n) and n >= 0, do: n

  defp parse_length(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_length(_), do: nil

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)

  # DevAuth puts the user_role_id on the conn assigns; sign/finalize prefer
  # server-trusted identity over whatever the client sends in the body.
  defp get_user_role_id(conn) do
    case conn.assigns[:current_user] do
      %{"user_role_id" => id} when id not in [nil, ""] -> id
      %{user_role_id: id} when id not in [nil, ""] -> id
      _ -> nil
    end
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
