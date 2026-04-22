defmodule FunSheep.Workers.TOCEscalationWorkerTest do
  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.Courses
  alias FunSheep.Courses.TOCRebase
  alias FunSheep.Repo
  alias FunSheep.Workers.TOCEscalationWorker

  defp create_course(attrs \\ %{}) do
    {:ok, course} =
      Courses.create_course(Map.merge(%{name: "Biology", subject: "Biology", grade: "10"}, attrs))

    course
  end

  defp backdate_proposal!(course, days) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    from_q =
      from(c in FunSheep.Courses.Course, where: c.id == ^course.id)

    Repo.update_all(from_q, set: [pending_toc_proposed_at: at])
    Courses.get_course!(course.id)
  end

  describe "perform/1" do
    test "skips courses with no pending proposal" do
      _course = create_course()
      assert :ok = perform_job(TOCEscalationWorker, %{})
    end

    test "skips pending proposals younger than 14 days" do
      course = create_course()

      # Create + mark pending a recent proposal.
      {:ok, toc} =
        TOCRebase.propose(course.id, "web", %{
          chapters: [%{"name" => "A"}],
          ocr_char_count: 500
        })

      {:ok, _} = TOCRebase.mark_pending(course, toc, nil)
      # Backdate to only 5 days old — shouldn't be touched.
      _ = backdate_proposal!(course, 5)

      assert :ok = perform_job(TOCEscalationWorker, %{})

      still_pending = Courses.get_course!(course.id)
      assert still_pending.pending_toc_id == toc.id
    end

    test "clears pending when DiscoveredTOC row has been deleted" do
      course = create_course()

      {:ok, toc} =
        TOCRebase.propose(course.id, "web", %{
          chapters: [%{"name" => "A"}],
          ocr_char_count: 500
        })

      {:ok, _} = TOCRebase.mark_pending(course, toc, nil)
      backdate_proposal!(course, 20)

      # Simulate the toc row having been deleted.
      Repo.delete!(toc)

      assert :ok = perform_job(TOCEscalationWorker, %{})

      reloaded = Courses.get_course!(course.id)
      assert is_nil(reloaded.pending_toc_id)
      assert is_nil(reloaded.pending_toc_proposed_at)
    end

    test "stale + attempts-safe → auto-apply (fallback completes the loop)" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()

        # Current TOC applied.
        {:ok, cur} =
          TOCRebase.propose(course.id, "web", %{
            chapters: [%{"name" => "Old Ch"}],
            ocr_char_count: 500
          })

        {:ok, _} = TOCRebase.apply(cur, course.id)

        # A better proposal, but no current attempts so it's attempts-safe.
        {:ok, pending} =
          TOCRebase.propose(course.id, "textbook_full", %{
            chapters: Enum.map(1..30, &%{"name" => "Ch #{&1}"}),
            ocr_char_count: 80_000
          })

        {:ok, _} = TOCRebase.mark_pending(Courses.get_course!(course.id), pending, nil)
        backdate_proposal!(course, 20)

        assert :ok = perform_job(TOCEscalationWorker, %{})

        reloaded = Courses.get_course!(course.id)
        assert is_nil(reloaded.pending_toc_id), "pending should be cleared after apply"

        # The new TOC is now current.
        current_now = TOCRebase.current(course.id)
        assert current_now.id == pending.id
      end)
    end
  end
end
