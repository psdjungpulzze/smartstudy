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
end
