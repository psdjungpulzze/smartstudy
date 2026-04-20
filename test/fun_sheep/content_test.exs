defmodule FunSheep.ContentTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Content
  alias FunSheep.Content.{UploadedMaterial, OcrPage}

  import FunSheep.ContentFixtures

  describe "uploaded_materials" do
    test "list_uploaded_materials/0 returns all materials" do
      material = create_uploaded_material()
      assert Content.list_uploaded_materials() |> Enum.map(& &1.id) |> Enum.member?(material.id)
    end

    test "get_uploaded_material!/1 returns the material" do
      material = create_uploaded_material()
      fetched = Content.get_uploaded_material!(material.id)
      assert fetched.id == material.id
      assert fetched.file_name == material.file_name
    end

    test "create_uploaded_material/1 with valid attrs creates a material" do
      user_role = create_user_role()
      course = create_course()

      attrs = %{
        file_path: "test/doc.pdf",
        file_name: "doc.pdf",
        file_type: "application/pdf",
        file_size: 2048,
        user_role_id: user_role.id,
        course_id: course.id
      }

      assert {:ok, %UploadedMaterial{} = material} = Content.create_uploaded_material(attrs)
      assert material.file_name == "doc.pdf"
      assert material.file_type == "application/pdf"
      assert material.file_size == 2048
      assert material.ocr_status == :pending
    end

    test "create_uploaded_material/1 with missing required fields returns error" do
      assert {:error, changeset} = Content.create_uploaded_material(%{})
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_uploaded_material/2 updates the material" do
      material = create_uploaded_material()

      assert {:ok, updated} =
               Content.update_uploaded_material(material, %{ocr_status: :processing})

      assert updated.ocr_status == :processing
    end

    test "delete_uploaded_material/1 deletes the material" do
      material = create_uploaded_material()
      assert {:ok, %UploadedMaterial{}} = Content.delete_uploaded_material(material)
      assert_raise Ecto.NoResultsError, fn -> Content.get_uploaded_material!(material.id) end
    end

    test "list_materials_by_user/1 returns materials for a specific user" do
      user_role = create_user_role()
      material = create_uploaded_material(%{user_role: user_role})
      _other_material = create_uploaded_material()

      materials = Content.list_materials_by_user(user_role.id)
      assert length(materials) == 1
      assert hd(materials).id == material.id
    end

    test "list_materials_by_course/1 returns materials for a specific course" do
      course = create_course()
      material = create_uploaded_material(%{course: course})
      _other_material = create_uploaded_material()

      materials = Content.list_materials_by_course(course.id)
      assert length(materials) == 1
      assert hd(materials).id == material.id
    end

    test "create_uploaded_material/1 defaults material_kind to :textbook" do
      material = create_uploaded_material()
      assert material.material_kind == :textbook
    end

    test "create_uploaded_material/1 accepts a valid material_kind" do
      user_role = create_user_role()
      course = create_course()

      attrs = %{
        file_path: "test/sample.pdf",
        file_name: "sample.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        material_kind: :sample_questions,
        user_role_id: user_role.id,
        course_id: course.id
      }

      assert {:ok, material} = Content.create_uploaded_material(attrs)
      assert material.material_kind == :sample_questions
    end

    test "create_uploaded_material/1 rejects an unknown material_kind" do
      user_role = create_user_role()
      course = create_course()

      attrs = %{
        file_path: "test/x.pdf",
        file_name: "x.pdf",
        file_type: "application/pdf",
        file_size: 1,
        material_kind: :not_a_real_kind,
        user_role_id: user_role.id,
        course_id: course.id
      }

      assert {:error, changeset} = Content.create_uploaded_material(attrs)
      assert %{material_kind: [_ | _]} = errors_on(changeset)
    end

    test "list_materials_by_course_and_kind/2 filters by a single kind" do
      course = create_course()
      textbook = create_uploaded_material(%{course: course, material_kind: :textbook})

      _notes =
        create_uploaded_material(%{course: course, material_kind: :lecture_notes})

      results = Content.list_materials_by_course_and_kind(course.id, :textbook)
      assert Enum.map(results, & &1.id) == [textbook.id]
    end

    test "list_materials_by_course_and_kind/2 filters by a list of kinds" do
      course = create_course()
      tb = create_uploaded_material(%{course: course, material_kind: :textbook})
      sup = create_uploaded_material(%{course: course, material_kind: :supplementary_book})
      _notes = create_uploaded_material(%{course: course, material_kind: :lecture_notes})

      results =
        Content.list_materials_by_course_and_kind(course.id, [:textbook, :supplementary_book])

      assert Enum.sort(Enum.map(results, & &1.id)) == Enum.sort([tb.id, sup.id])
    end

    test "course_material_kinds/1 returns distinct kinds present for a course" do
      course = create_course()
      create_uploaded_material(%{course: course, material_kind: :textbook})
      create_uploaded_material(%{course: course, material_kind: :textbook})
      create_uploaded_material(%{course: course, material_kind: :sample_questions})

      kinds = Content.course_material_kinds(course.id)
      assert Enum.sort(kinds) == [:sample_questions, :textbook]
    end
  end

  describe "ocr_pages" do
    test "create_ocr_page/1 with valid attrs creates a page" do
      material = create_uploaded_material()

      attrs = %{
        material_id: material.id,
        page_number: 1,
        extracted_text: "Some text",
        bounding_boxes: %{"blocks" => []},
        images: %{"pages" => []}
      }

      assert {:ok, %OcrPage{} = page} = Content.create_ocr_page(attrs)
      assert page.page_number == 1
      assert page.extracted_text == "Some text"
      assert page.material_id == material.id
    end

    test "create_ocr_page/1 validates page_number > 0" do
      material = create_uploaded_material()

      attrs = %{material_id: material.id, page_number: 0}
      assert {:error, changeset} = Content.create_ocr_page(attrs)
      assert %{page_number: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "create_ocr_page/1 requires material_id" do
      attrs = %{page_number: 1}
      assert {:error, changeset} = Content.create_ocr_page(attrs)
      assert %{material_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_ocr_page!/1 returns the page" do
      material = create_uploaded_material()
      {:ok, page} = Content.create_ocr_page(%{material_id: material.id, page_number: 1})

      fetched = Content.get_ocr_page!(page.id)
      assert fetched.id == page.id
    end

    test "list_ocr_pages_by_material/1 returns pages ordered by page_number" do
      material = create_uploaded_material()

      {:ok, _page2} =
        Content.create_ocr_page(%{material_id: material.id, page_number: 2, extracted_text: "p2"})

      {:ok, _page1} =
        Content.create_ocr_page(%{material_id: material.id, page_number: 1, extracted_text: "p1"})

      pages = Content.list_ocr_pages_by_material(material.id)
      assert length(pages) == 2
      assert Enum.at(pages, 0).page_number == 1
      assert Enum.at(pages, 1).page_number == 2
    end

    test "list_ocr_pages_by_material/1 only returns pages for specified material" do
      material1 = create_uploaded_material()
      material2 = create_uploaded_material()

      {:ok, _} = Content.create_ocr_page(%{material_id: material1.id, page_number: 1})
      {:ok, _} = Content.create_ocr_page(%{material_id: material2.id, page_number: 1})

      pages = Content.list_ocr_pages_by_material(material1.id)
      assert length(pages) == 1
    end

    test "update_ocr_page/2 updates the page" do
      material = create_uploaded_material()
      {:ok, page} = Content.create_ocr_page(%{material_id: material.id, page_number: 1})

      assert {:ok, updated} = Content.update_ocr_page(page, %{extracted_text: "Updated text"})
      assert updated.extracted_text == "Updated text"
    end

    test "delete_ocr_page/1 deletes the page" do
      material = create_uploaded_material()
      {:ok, page} = Content.create_ocr_page(%{material_id: material.id, page_number: 1})

      assert {:ok, %OcrPage{}} = Content.delete_ocr_page(page)
      assert_raise Ecto.NoResultsError, fn -> Content.get_ocr_page!(page.id) end
    end
  end

end
