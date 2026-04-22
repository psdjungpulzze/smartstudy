defmodule FunSheep.Admin.JobsTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Admin.Jobs
  alias FunSheep.Repo

  describe "categorize/1" do
    test "detects interactor unavailable" do
      assert Jobs.categorize(%{errors: [%{"error" => "Interactor is unavailable"}]}) ==
               :interactor_unavailable

      assert Jobs.categorize(%{errors: [%{"error" => "econnrefused on Interactor"}]}) ==
               :interactor_unavailable
    end

    test "detects OCR failures" do
      assert Jobs.categorize(%{errors: [%{"error" => "OCR failed: no text"}]}) == :ocr_failed
      assert Jobs.categorize(%{errors: [%{"error" => "Google Vision failed"}]}) == :ocr_failed
    end

    test "detects validation rejections" do
      assert Jobs.categorize(%{errors: [%{"error" => "validator rejected all"}]}) ==
               :validation_rejected

      assert Jobs.categorize(%{errors: [%{"error" => "assistant_not_found"}]}) ==
               :validation_rejected
    end

    test "detects rate limits" do
      assert Jobs.categorize(%{errors: [%{"error" => "HTTP 429 Too Many Requests"}]}) ==
               :rate_limited

      assert Jobs.categorize(%{errors: [%{"error" => "rate-limited by vendor"}]}) ==
               :rate_limited
    end

    test "detects timeouts" do
      assert Jobs.categorize(%{errors: [%{"error" => "timeout after 60s"}]}) == :timeout
      assert Jobs.categorize(%{errors: [%{"error" => "timed out waiting"}]}) == :timeout
    end

    test "falls back to :other" do
      assert Jobs.categorize(%{errors: []}) == :other
      assert Jobs.categorize(%{errors: [%{"error" => "random gibberish"}]}) == :other
      assert Jobs.categorize(%{}) == :other
    end
  end

  describe "count_failures/1 and list_failed/2" do
    setup do
      insert_failed_job(%{
        worker: "FunSheep.Workers.CourseDiscoveryWorker",
        queue: "ai",
        args: %{"course_id" => Ecto.UUID.generate()},
        errors: [%{"attempt" => 1, "error" => "Interactor unavailable"}]
      })

      insert_failed_job(%{
        worker: "FunSheep.Workers.OCRMaterialWorker",
        queue: "ocr",
        args: %{"material_id" => Ecto.UUID.generate()},
        errors: [%{"attempt" => 1, "error" => "OCR failed: no text"}]
      })

      :ok
    end

    test "counts recent failures" do
      assert Jobs.count_failures() == 2
    end

    test "list_failed returns enriched rows" do
      rows = Jobs.list_failed(%{}, limit: 10)
      assert length(rows) == 2
      assert Enum.all?(rows, &Map.has_key?(&1, :worker_short))
      assert Enum.all?(rows, &Map.has_key?(&1, :summary))
      assert Enum.all?(rows, &Map.has_key?(&1, :category))
    end

    test "by_worker groups counts" do
      rows = Jobs.count_by_worker()
      assert Enum.any?(rows, &(&1.worker == "FunSheep.Workers.CourseDiscoveryWorker"))
      assert Enum.any?(rows, &(&1.worker == "FunSheep.Workers.OCRMaterialWorker"))
    end

    test "count_by_category bucketizes" do
      rows = Jobs.count_by_category()
      cats = Enum.map(rows, & &1.category)
      assert :interactor_unavailable in cats
      assert :ocr_failed in cats
    end

    test "worker filter narrows results" do
      rows = Jobs.list_failed(%{worker: "FunSheep.Workers.OCRMaterialWorker"}, limit: 10)
      assert length(rows) == 1
      assert hd(rows).worker_short == "OCRMaterialWorker"
    end
  end

  describe "summarize_args/4" do
    test "uses course name when args include course_id" do
      {:ok, school} =
        FunSheep.Accounts.create_user_role(%{
          interactor_user_id: Ecto.UUID.generate(),
          role: :student,
          email: "s@x.com",
          display_name: "S"
        })

      {:ok, course} =
        FunSheep.Courses.create_course(%{
          name: "Biology 101",
          subject: "Biology",
          grade: "10",
          created_by_id: school.id
        })

      job = %Oban.Job{id: 1, args: %{"course_id" => course.id}, errors: [], worker: "X"}
      summary = Jobs.summarize_args(job, %{course.id => course}, %{}, nil)
      assert summary =~ "Biology 101"
    end

    test "falls back to raw id when no context map is provided" do
      job = %Oban.Job{id: 1, args: %{"course_id" => "abc123"}, errors: [], worker: "X"}
      summary = Jobs.summarize_args(job)
      assert summary =~ "abc123"
    end

    test "reports '(no args)' when args are empty" do
      job = %Oban.Job{id: 1, args: %{}, errors: [], worker: "X"}
      assert Jobs.summarize_args(job) == "(no args)"
    end

    test "falls back to first 2 args when no domain ids present" do
      job = %Oban.Job{
        id: 1,
        args: %{"mode" => "from_curriculum", "count" => 10},
        errors: [],
        worker: "X"
      }

      summary = Jobs.summarize_args(job)
      assert summary =~ "mode=" or summary =~ "count="
    end

    test "includes question count when args carry question_ids list" do
      job = %Oban.Job{id: 1, args: %{"question_ids" => ["a", "b", "c"]}, errors: [], worker: "X"}
      assert Jobs.summarize_args(job) =~ "3 questions"
    end

    test "uses material filename when materials_map carries it" do
      material = %FunSheep.Content.UploadedMaterial{
        id: "mat-abc",
        file_name: "chapter-1.pdf"
      }

      job = %Oban.Job{id: 1, args: %{"material_id" => "mat-abc"}, errors: [], worker: "X"}
      summary = Jobs.summarize_args(job, %{}, %{"mat-abc" => material}, nil)
      assert summary =~ "chapter-1.pdf"
    end
  end

  describe "retry_job/2 and cancel_job/2" do
    test "retry re-queues the job and writes an audit log" do
      job = insert_failed_job(%{worker: "Worker.A"})
      actor = %{"user_role_id" => nil, "email" => "admin@test.com"}

      assert :ok = Jobs.retry_job(job.id, actor)

      logs = FunSheep.Admin.list_audit_logs(limit: 5)
      assert Enum.any?(logs, &(&1.action == "admin.job.retry"))
    end

    test "cancel marks the job cancelled and writes an audit log" do
      job = insert_failed_job(%{worker: "Worker.B"})
      actor = %{"user_role_id" => nil, "email" => "admin@test.com"}

      assert :ok = Jobs.cancel_job(job.id, actor)

      logs = FunSheep.Admin.list_audit_logs(limit: 5)
      assert Enum.any?(logs, &(&1.action == "admin.job.cancel"))
    end
  end

  describe "get_failed_job!/1" do
    test "returns an enriched row" do
      job = insert_failed_job(%{worker: "Worker.C"})
      row = Jobs.get_failed_job!(job.id)
      assert row.job.id == job.id
      assert row.worker_short == "C"
    end
  end

  describe "list_failed/2 pagination" do
    test "respects offset and limit" do
      for i <- 1..5 do
        insert_failed_job(%{worker: "Worker.Pager#{i}"})
      end

      page1 = Jobs.list_failed(%{}, limit: 2, offset: 0)
      page2 = Jobs.list_failed(%{}, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2

      ids_page1 = Enum.map(page1, & &1.job.id)
      ids_page2 = Enum.map(page2, & &1.job.id)
      assert MapSet.disjoint?(MapSet.new(ids_page1), MapSet.new(ids_page2))
    end
  end

  # --- helpers ---------------------------------------------------------

  defp insert_failed_job(attrs) do
    %Oban.Job{
      state: "discarded",
      queue: "default",
      worker: "FunSheep.Workers.UnknownWorker",
      args: %{},
      errors: [],
      max_attempts: 3,
      attempt: 3,
      inserted_at: DateTime.utc_now(),
      attempted_at: DateTime.utc_now(),
      discarded_at: DateTime.utc_now()
    }
    |> Map.merge(attrs)
    |> then(&struct(Oban.Job, Map.from_struct(&1)))
    |> Repo.insert!()
  end
end
