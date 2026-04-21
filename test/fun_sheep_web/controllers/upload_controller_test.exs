defmodule FunSheepWeb.UploadControllerTest do
  use FunSheepWeb.ConnCase, async: false

  import FunSheep.ContentFixtures

  alias FunSheep.Content

  @tmp_dir System.tmp_dir!()

  defp upload_plug(filename, content_type \\ "application/pdf", body \\ "fake-pdf-bytes") do
    path = Path.join(@tmp_dir, "uploadctrl_#{System.unique_integer([:positive])}_#{filename}")
    File.write!(path, body)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: content_type
    }
  end

  defp base_params(user_role_id) do
    %{
      "batch_id" => Ecto.UUID.generate(),
      "user_role_id" => user_role_id
    }
  end

  describe "POST /api/upload" do
    test "defaults material_kind to :textbook when not supplied", %{conn: conn} do
      user_role = create_user_role()

      params =
        Map.merge(base_params(user_role.id), %{
          "file" => upload_plug("chapter1.pdf")
        })

      conn = post(conn, "/api/upload", params)
      body = json_response(conn, 200)

      assert body["material_kind"] == "textbook"
      material = Content.get_uploaded_material!(body["id"])
      assert material.material_kind == :textbook
    end

    test "accepts a valid material_kind param", %{conn: conn} do
      user_role = create_user_role()

      params =
        Map.merge(base_params(user_role.id), %{
          "file" => upload_plug("past_exam.pdf"),
          "material_kind" => "sample_questions"
        })

      conn = post(conn, "/api/upload", params)
      body = json_response(conn, 200)

      assert body["material_kind"] == "sample_questions"
      material = Content.get_uploaded_material!(body["id"])
      assert material.material_kind == :sample_questions
    end

    test "falls back to :textbook when material_kind is unknown", %{conn: conn} do
      user_role = create_user_role()

      params =
        Map.merge(base_params(user_role.id), %{
          "file" => upload_plug("mystery.pdf"),
          "material_kind" => "definitely_not_a_kind"
        })

      conn = post(conn, "/api/upload", params)
      body = json_response(conn, 200)

      assert body["material_kind"] == "textbook"
    end
  end

  describe "POST /api/uploads/sign" do
    test "returns a Local upload_url and matching object_key", %{conn: conn} do
      user_role = create_user_role()
      batch_id = Ecto.UUID.generate()

      params = %{
        "batch_id" => batch_id,
        "user_role_id" => user_role.id,
        "file_name" => "chapter1.pdf",
        "file_type" => "application/pdf",
        "file_size" => 12_345
      }

      conn = post(conn, "/api/uploads/sign", params)
      body = json_response(conn, 200)

      assert body["object_key"] == "staging/#{batch_id}/chapter1.pdf"
      assert body["upload_url"] =~ "/api/uploads/local/"
      assert body["upload_url"] =~ body["object_key"]
      assert body["expires_at"]
    end

    test "includes folder in object key when folder_name is set", %{conn: conn} do
      user_role = create_user_role()
      batch_id = Ecto.UUID.generate()

      params = %{
        "batch_id" => batch_id,
        "user_role_id" => user_role.id,
        "file_name" => "nested.pdf",
        "file_type" => "application/pdf",
        "file_size" => 42,
        "folder_name" => "my-folder"
      }

      conn = post(conn, "/api/uploads/sign", params)
      body = json_response(conn, 200)

      assert body["object_key"] == "staging/#{batch_id}/my-folder/nested.pdf"
    end

    test "400 for invalid batch_id", %{conn: conn} do
      user_role = create_user_role()

      conn =
        post(conn, "/api/uploads/sign", %{
          "batch_id" => "not-a-uuid",
          "user_role_id" => user_role.id,
          "file_name" => "x.pdf"
        })

      assert json_response(conn, 400)["error"] =~ "invalid batch_id"
    end

    test "401 without user_role_id", %{conn: conn} do
      conn =
        post(conn, "/api/uploads/sign", %{
          "batch_id" => Ecto.UUID.generate(),
          "file_name" => "x.pdf"
        })

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "POST /api/uploads/finalize" do
    setup do
      # Finalize calls Storage.object_info/1 to verify the upload actually
      # landed. We put a file at the expected key via the same Storage
      # module so the check passes in tests.
      user_role = create_user_role()
      batch_id = Ecto.UUID.generate()
      object_key = "staging/#{batch_id}/final.pdf"

      {:ok, _} =
        FunSheep.Storage.put(object_key, "fake-pdf-bytes", content_type: "application/pdf")

      on_exit(fn -> FunSheep.Storage.delete(object_key) end)

      %{user_role: user_role, batch_id: batch_id, object_key: object_key}
    end

    test "creates UploadedMaterial when object exists in storage",
         %{conn: conn, user_role: user_role, batch_id: batch_id, object_key: object_key} do
      params = %{
        "batch_id" => batch_id,
        "user_role_id" => user_role.id,
        "object_key" => object_key,
        "file_name" => "final.pdf",
        "file_type" => "application/pdf",
        "material_kind" => "textbook"
      }

      conn = post(conn, "/api/uploads/finalize", params)
      body = json_response(conn, 200)

      material = Content.get_uploaded_material!(body["id"])
      assert material.file_path == object_key
      # Finalize MUST use the actual storage size, not a client-declared one
      # — this prevents a malicious client from lying about the size.
      assert material.file_size == byte_size("fake-pdf-bytes")
      assert material.material_kind == :textbook
    end

    test "rejects object_key outside the batch's staging prefix",
         %{conn: conn, user_role: user_role, batch_id: batch_id} do
      params = %{
        "batch_id" => batch_id,
        "user_role_id" => user_role.id,
        "object_key" => "staging/#{Ecto.UUID.generate()}/other.pdf",
        "file_name" => "other.pdf"
      }

      conn = post(conn, "/api/uploads/finalize", params)
      assert json_response(conn, 400)["error"] =~ "outside batch prefix"
    end

    test "404 when the storage object does not exist",
         %{conn: conn, user_role: user_role, batch_id: batch_id} do
      params = %{
        "batch_id" => batch_id,
        "user_role_id" => user_role.id,
        "object_key" => "staging/#{batch_id}/ghost.pdf",
        "file_name" => "ghost.pdf"
      }

      conn = post(conn, "/api/uploads/finalize", params)
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "PUT /api/uploads/local/:token/*key" do
    test "writes body to Local storage when token matches", %{conn: conn} do
      key = "staging/#{Ecto.UUID.generate()}/put.pdf"
      token = FunSheep.Storage.Local.token_for(key)

      conn =
        conn
        |> put_req_header("content-type", "application/pdf")
        |> put("/api/uploads/local/#{token}/#{key}", "body-bytes")

      assert json_response(conn, 200)["status"] == "ok"
      assert {:ok, "body-bytes"} = FunSheep.Storage.get(key)
      FunSheep.Storage.delete(key)
    end

    test "403 when token doesn't match the key", %{conn: conn} do
      key = "staging/#{Ecto.UUID.generate()}/put.pdf"

      conn =
        conn
        |> put_req_header("content-type", "application/pdf")
        |> put("/api/uploads/local/not-the-token/#{key}", "body-bytes")

      assert json_response(conn, 403)["error"] =~ "invalid token"
    end
  end
end
