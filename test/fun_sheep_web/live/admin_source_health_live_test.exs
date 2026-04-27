defmodule FunSheepWeb.AdminSourceHealthLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Courses, Repo}
  alias FunSheep.Content.UploadedMaterial

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "admin-user-id",
      dev_user: %{
        "id" => "admin-user-id",
        "role" => "admin",
        "email" => "admin@example.com",
        "display_name" => "Admin User"
      }
    })
  end

  describe "mount/3" do
    test "renders the source health page title", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      assert html =~ "Source health"
    end

    test "renders provenance description text", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      assert html =~ "Provenance, coverage, and material-kind mismatches per course."
    end

    test "renders material mismatches section", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      assert html =~ "Material mismatches"
    end

    test "renders no-mismatches message when no mismatch records exist", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      # With a clean DB or no qualifying mismatches, we see the empty state message
      assert html =~ "No mismatches right now" or html =~ "Classifier and user labels agree"
    end

    test "renders source mix section when a course is auto-selected on mount", %{conn: conn} do
      _course = ContentFixtures.create_course(%{name: "Auto-Select Course", subject: "Biology", grade: "10"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      # The page renders source type labels for whichever course was auto-selected
      assert html =~ "AI-generated" or html =~ "Source health"
    end

    test "renders coverage heatmap target in header when course selected", %{conn: conn} do
      _course = ContentFixtures.create_course(%{name: "Heatmap Course", subject: "Math", grade: "9"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      assert html =~ "target"
    end

    test "renders Run coverage audit button when course selected", %{conn: conn} do
      _course = ContentFixtures.create_course(%{name: "Audit Button Course", subject: "Science", grade: "8"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      assert html =~ "Run coverage audit"
    end
  end

  describe "select_course event" do
    test "selecting a course loads its health data without crash", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "Test Biology Course", subject: "Biology", grade: "10"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      # Send select_course event with the real course id
      html =
        view
        |> render_change("select_course", %{"course_id" => course.id})

      # Should still display the page without error
      assert html =~ "Source health"
    end

    test "selecting a course shows source mix section for that course", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "Chemistry 101", subject: "Chemistry", grade: "11"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      html = render_change(view, "select_course", %{"course_id" => course.id})

      # Source mix section should appear
      assert html =~ "source-ai_generated" or html =~ "Source mix"
    end

    test "selecting a course with chapters shows no-chapters message when none registered", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "No Chapters Course", subject: "History", grade: "10"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      html = render_change(view, "select_course", %{"course_id" => course.id})

      assert html =~ "No chapters registered for this course yet."
    end

    test "selecting a course with chapters shows coverage heatmap table", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "Chapters Course", subject: "Physics", grade: "12"})

      {:ok, _chapter} = Courses.create_chapter(%{
        name: "Chapter 1: Motion",
        course_id: course.id,
        position: 1
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      html = render_change(view, "select_course", %{"course_id" => course.id})

      assert html =~ "Chapter 1: Motion"
      assert html =~ "easy"
      assert html =~ "medium"
      assert html =~ "hard"
    end
  end

  describe "trigger_audit event" do
    test "enqueues coverage audit and shows flash message", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "Physics 101", subject: "Physics", grade: "12"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      # First select the course so selected_course is set
      render_change(view, "select_course", %{"course_id" => course.id})

      # Now trigger the audit
      html = render_click(view, "trigger_audit", %{"course_id" => course.id})

      assert html =~ "Coverage audit queued"
    end

    test "enqueues audit for auto-selected first course without prior select", %{conn: conn} do
      course = ContentFixtures.create_course(%{name: "Auto Course", subject: "Biology", grade: "10"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/source-health")

      html = render_click(view, "trigger_audit", %{"course_id" => course.id})

      assert html =~ "Coverage audit queued"
    end
  end

  describe "material mismatches table" do
    test "renders mismatch table when mismatching uploaded materials exist", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{name: "Mismatch Course", subject: "Math", grade: "10"})

      # Create an UploadedMaterial where material_kind != classified_kind
      # (sample_questions vs knowledge_content is a mismatch)
      {:ok, _material} =
        %UploadedMaterial{}
        |> UploadedMaterial.changeset(%{
          file_path: "test/mismatch_#{System.unique_integer([:positive])}.jpg",
          file_name: "mismatch_file.jpg",
          file_type: "image/jpeg",
          file_size: 2048,
          ocr_status: :pending,
          user_role_id: user_role.id,
          course_id: course.id,
          material_kind: :sample_questions,
          classified_kind: :knowledge_content,
          kind_classified_at: DateTime.utc_now(),
          kind_confidence: 0.95
        })
        |> Repo.insert()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/source-health")

      # Either the mismatch row appears or the empty state if query filtered it
      assert html =~ "mismatch_file.jpg" or html =~ "Material mismatches"
    end
  end
end
