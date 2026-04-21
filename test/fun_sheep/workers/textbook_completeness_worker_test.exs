defmodule FunSheep.Workers.TextbookCompletenessWorkerTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Content
  alias FunSheep.ContentFixtures
  alias FunSheep.Workers.TextbookCompletenessWorker

  describe "parse_response/1" do
    test "parses well-formed JSON" do
      response = ~S({
        "toc_detected": true,
        "chapters": ["Intro", "Cells"],
        "coverage_score": 0.75,
        "notes": "Most chapters present; ch. 12 missing"
      })

      assert {:ok, parsed} = TextbookCompletenessWorker.parse_response(response)
      assert parsed.toc_detected == true
      assert parsed.score == 0.75
      assert parsed.notes =~ "Most chapters present"
      assert parsed.notes =~ "2 chapters detected"
    end

    test "strips markdown code fences" do
      response = """
      ```json
      {"toc_detected": false, "chapters": [], "coverage_score": 0.2, "notes": "No TOC found"}
      ```
      """

      assert {:ok, parsed} = TextbookCompletenessWorker.parse_response(response)
      assert parsed.toc_detected == false
      assert parsed.score == 0.2
    end

    test "clamps out-of-range scores" do
      response = ~S({"toc_detected": true, "chapters": [], "coverage_score": 1.7, "notes": ""})
      assert {:ok, %{score: 1.0}} = TextbookCompletenessWorker.parse_response(response)

      response = ~S({"toc_detected": true, "chapters": [], "coverage_score": -0.3, "notes": ""})
      assert {:ok, %{score: 0.0}} = TextbookCompletenessWorker.parse_response(response)
    end

    test "rejects missing score" do
      response = ~S({"toc_detected": true, "chapters": [], "notes": "hmm"})

      assert {:error, :missing_coverage_score} =
               TextbookCompletenessWorker.parse_response(response)
    end

    test "rejects invalid JSON" do
      assert {:error, :invalid_json} = TextbookCompletenessWorker.parse_response("not json")
    end
  end

  describe "perform/1" do
    test "no-ops for non-textbook materials" do
      material = ContentFixtures.create_uploaded_material(%{material_kind: :lecture_notes})

      assert :ok = perform_job(material.id)

      # Should not have been updated
      reloaded = Content.get_uploaded_material!(material.id)
      assert reloaded.completeness_checked_at == nil
    end

    test "no-ops when OCR is still pending" do
      material =
        ContentFixtures.create_uploaded_material(%{material_kind: :textbook, ocr_status: :pending})

      assert :ok = perform_job(material.id)

      reloaded = Content.get_uploaded_material!(material.id)
      assert reloaded.completeness_checked_at == nil
    end

    test "fails honestly when OCR text is empty" do
      material =
        ContentFixtures.create_uploaded_material(%{
          material_kind: :textbook,
          ocr_status: :completed
        })

      assert :ok = perform_job(material.id)

      reloaded = Content.get_uploaded_material!(material.id)
      assert reloaded.completeness_score == nil
      assert reloaded.completeness_notes =~ "No OCR text"
      assert reloaded.toc_detected == false
      assert reloaded.completeness_checked_at != nil
    end

    test "records a failure when assistant is not configured (mock mode)" do
      material =
        ContentFixtures.create_uploaded_material(%{
          material_kind: :textbook,
          ocr_status: :completed
        })

      # Attach some OCR text so the worker actually tries to call the AI
      for i <- 1..3 do
        %FunSheep.Content.OcrPage{}
        |> FunSheep.Content.OcrPage.changeset(%{
          page_number: i,
          extracted_text: "Sample textbook text on page #{i}",
          material_id: material.id
        })
        |> Repo.insert!()
      end

      # In test env interactor_mock is on and list_assistants returns [], so
      # `resolve_assistant("textbook_completeness")` returns
      # `{:error, {:assistant_not_found, _}}` — exactly the "fail honestly" path.
      assert {:error, _} = perform_job(material.id)

      reloaded = Content.get_uploaded_material!(material.id)
      assert reloaded.completeness_score == nil
      assert reloaded.completeness_notes =~ "Completeness check could not run"
      assert reloaded.completeness_checked_at != nil
    end
  end

  defp perform_job(material_id) do
    TextbookCompletenessWorker.perform(%Oban.Job{args: %{"material_id" => material_id}})
  end
end
