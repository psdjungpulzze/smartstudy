defmodule FunSheep.Workers.CreditWorkersTest do
  use FunSheep.DataCase, async: true
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.{Accounts, Credits, ContentFixtures}

  alias FunSheep.Workers.{
    CreditReferralCheckWorker,
    CreditMaterialUploadWorker,
    CreditTestCreatedWorker
  }

  # ── Fixtures ────────────────────────────────────────────────────────────────

  defp create_teacher do
    {:ok, ur} =
      Accounts.create_user_role(%{
        interactor_user_id: "teacher_#{System.unique_integer([:positive])}",
        role: :teacher,
        email: "teacher#{System.unique_integer([:positive])}@test.com",
        display_name: "Teacher"
      })

    ur
  end

  defp create_student do
    {:ok, ur} =
      Accounts.create_user_role(%{
        interactor_user_id: "student_#{System.unique_integer([:positive])}",
        role: :student,
        email: "student#{System.unique_integer([:positive])}@test.com",
        display_name: "Student"
      })

    ur
  end

  defp activate_student_for_teacher(teacher, student) do
    {:ok, sg} = Accounts.invite_guardian(teacher.id, student.email, :teacher)
    {:ok, activated_sg} = Accounts.accept_guardian_invite(sg.id)
    activated_sg
  end

  # ── CreditReferralCheckWorker ────────────────────────────────────────────────

  describe "CreditReferralCheckWorker" do
    test "does not award credits when student count is below batch threshold" do
      teacher = create_teacher()

      for _ <- 1..9 do
        student = create_student()
        activate_student_for_teacher(teacher, student)
      end

      sg_id = Ecto.UUID.generate()

      assert :ok =
               perform_job(CreditReferralCheckWorker, %{
                 "teacher_user_role_id" => teacher.id,
                 "student_guardian_id" => sg_id
               })

      assert Credits.get_balance(teacher.id) == 0
    end

    test "awards 1 credit (4 quarter-units) when teacher reaches 10 active students" do
      teacher = create_teacher()
      last_sg = nil

      sg_ids =
        for _ <- 1..10 do
          student = create_student()
          sg = activate_student_for_teacher(teacher, student)
          sg.id
        end

      sg_id = List.last(sg_ids)

      assert :ok =
               perform_job(CreditReferralCheckWorker, %{
                 "teacher_user_role_id" => teacher.id,
                 "student_guardian_id" => sg_id
               })

      assert Credits.get_balance(teacher.id) == 1
    end

    test "is idempotent — running again with the same sg_id does not double-award" do
      teacher = create_teacher()

      sg_ids =
        for _ <- 1..10 do
          student = create_student()
          sg = activate_student_for_teacher(teacher, student)
          sg.id
        end

      sg_id = List.last(sg_ids)

      assert :ok =
               perform_job(CreditReferralCheckWorker, %{
                 "teacher_user_role_id" => teacher.id,
                 "student_guardian_id" => sg_id
               })

      assert :ok =
               perform_job(CreditReferralCheckWorker, %{
                 "teacher_user_role_id" => teacher.id,
                 "student_guardian_id" => sg_id
               })

      # Only 1 credit despite two runs
      assert Credits.get_balance(teacher.id) == 1
    end
  end

  # ── CreditMaterialUploadWorker ───────────────────────────────────────────────

  describe "CreditMaterialUploadWorker" do
    test "awards 2 quarter-units (0 whole credits) to a teacher for an uploaded material" do
      teacher = create_teacher()

      material =
        ContentFixtures.create_uploaded_material(%{
          user_role: teacher
        })

      assert :ok =
               perform_job(CreditMaterialUploadWorker, %{
                 "uploaded_material_id" => material.id
               })

      # 2 quarter-units = 0 whole credits
      assert Credits.get_balance(teacher.id) == 0
      # But balance_quarter_units is 2
      assert Credits.get_balance_quarter_units(teacher.id) == 2
    end

    test "awards full credit when 4 quarter-units accumulated" do
      teacher = create_teacher()

      for _ <- 1..2 do
        m = ContentFixtures.create_uploaded_material(%{user_role: teacher})

        perform_job(CreditMaterialUploadWorker, %{"uploaded_material_id" => m.id})
      end

      # 4 quarter-units = 1 whole credit
      assert Credits.get_balance(teacher.id) == 1
    end

    test "is idempotent — same material_id does not double-award" do
      teacher = create_teacher()
      material = ContentFixtures.create_uploaded_material(%{user_role: teacher})

      perform_job(CreditMaterialUploadWorker, %{"uploaded_material_id" => material.id})
      perform_job(CreditMaterialUploadWorker, %{"uploaded_material_id" => material.id})

      assert Credits.get_balance_quarter_units(teacher.id) == 2
    end

    test "does not award credits to a student who uploads material" do
      student = create_student()
      material = ContentFixtures.create_uploaded_material(%{user_role: student})

      assert :ok =
               perform_job(CreditMaterialUploadWorker, %{
                 "uploaded_material_id" => material.id
               })

      assert Credits.get_balance_quarter_units(student.id) == 0
    end
  end

  # ── CreditTestCreatedWorker ──────────────────────────────────────────────────

  describe "CreditTestCreatedWorker" do
    test "awards 1 quarter-unit to a teacher who creates a test schedule" do
      teacher = create_teacher()
      course = ContentFixtures.create_course()

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Test Schedule",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => []},
          user_role_id: teacher.id,
          course_id: course.id
        })

      # The worker may have been enqueued automatically; drain it cleanly
      # by testing via perform_job directly with the schedule id.
      assert :ok =
               perform_job(CreditTestCreatedWorker, %{
                 "test_schedule_id" => schedule.id
               })

      # 1 quarter-unit awarded
      assert Credits.get_balance_quarter_units(teacher.id) >= 1
    end

    test "is idempotent — same schedule_id does not double-award" do
      teacher = create_teacher()
      course = ContentFixtures.create_course()

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Test Schedule",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => []},
          user_role_id: teacher.id,
          course_id: course.id
        })

      perform_job(CreditTestCreatedWorker, %{"test_schedule_id" => schedule.id})
      perform_job(CreditTestCreatedWorker, %{"test_schedule_id" => schedule.id})

      # Only 1 quarter-unit despite two runs
      # (The automatic enqueue from create_test_schedule may add more, but
      # direct duplicate perform_job calls should be idempotent)
      ledger = Credits.list_ledger(teacher.id)
      test_entries = Enum.filter(ledger, &(&1.source == "test_created"))
      assert length(test_entries) == 1
    end

    test "does not award credits to a student" do
      student = create_student()
      course = ContentFixtures.create_course()

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Test Schedule",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => []},
          user_role_id: student.id,
          course_id: course.id
        })

      assert :ok =
               perform_job(CreditTestCreatedWorker, %{
                 "test_schedule_id" => schedule.id
               })

      assert Credits.get_balance_quarter_units(student.id) == 0
    end
  end
end
