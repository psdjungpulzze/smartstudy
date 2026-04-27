defmodule FunSheepWeb.ExamSimulationLive.ResultsTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Repo}
  alias FunSheep.Assessments.ExamSimulations

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  # Creates a question directly and returns it
  defp create_question(course) do
    {:ok, q} =
      %FunSheep.Questions.Question{}
      |> FunSheep.Questions.Question.changeset(%{
        content: "What is the powerhouse of the cell?",
        answer: "Mitochondria",
        question_type: :multiple_choice,
        difficulty: :easy,
        course_id: course.id,
        source_type: :ai_generated,
        explanation: "The mitochondria produces ATP energy for the cell."
      })
      |> Repo.insert()

    q
  end

  defp create_completed_session(user_role, course, overrides \\ %{}) do
    now = DateTime.utc_now(:second)

    defaults = %{
      user_role_id: user_role.id,
      course_id: course.id,
      time_limit_seconds: 2700,
      started_at: DateTime.add(now, -45, :minute),
      question_ids_order: [],
      section_boundaries: [
        %{
          "name" => "Math",
          "question_count" => 0,
          "time_budget_seconds" => 2700,
          "start_index" => 0
        }
      ],
      status: "submitted",
      submitted_at: now,
      score_correct: 3,
      score_total: 5,
      score_pct: 60.0,
      answers: %{},
      section_scores: %{
        "Math" => %{"correct" => 3, "total" => 5, "time_seconds" => 1800}
      }
    }

    {:ok, session} = ExamSimulations.create_session(Map.merge(defaults, overrides))
    session
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Results Test Course"})
    %{user_role: user_role, course: course}
  end

  describe "mount" do
    test "renders results page for a completed session", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      session = create_completed_session(ur, c)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "Results Test Course"
      assert html =~ "Results" or html =~ "Score" or html =~ "60"
    end

    test "redirects to dashboard when session belongs to another user", %{
      conn: conn,
      course: c
    } do
      other_user = ContentFixtures.create_user_role()
      session = create_completed_session(other_user, c)

      my_user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, my_user)

      assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
               live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")
    end

    test "shows section summary", %{conn: conn, user_role: ur, course: c} do
      session = create_completed_session(ur, c)

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "Math" or html =~ "section"
    end

    test "shows timed_out status message", %{conn: conn, user_role: ur, course: c} do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      # timed_out session with one unanswered question
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 1800,
          started_at: DateTime.add(now, -35, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Reading",
              "question_count" => 1,
              "time_budget_seconds" => 1800,
              "start_index" => 0
            }
          ],
          status: "timed_out",
          submitted_at: now,
          score_correct: 0,
          score_total: 1,
          score_pct: 0.0,
          answers: %{},
          section_scores: %{"Reading" => %{"correct" => 0, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "Time ran out"
      # The timed_out unanswered insight should appear
      assert html =~ "unanswered"
    end

    test "shows insights for over-budget sections", %{conn: conn, user_role: ur, course: c} do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      # The question has time_spent_seconds = 600 but budget is 300 → over budget
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 600,
          started_at: DateTime.add(now, -20, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Science",
              "question_count" => 1,
              "time_budget_seconds" => 300,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 600
            }
          },
          section_scores: %{"Science" => %{"correct" => 1, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # Over-budget insight message should appear
      assert html =~ "more time than budgeted"
      assert html =~ "Science"
      # Section should show "over" time status
      assert html =~ "over"
    end

    test "shows insight for flagged but unanswered questions", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 1800,
          started_at: DateTime.add(now, -30, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Verbal",
              "question_count" => 1,
              "time_budget_seconds" => 1800,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 0,
          score_total: 1,
          score_pct: 0.0,
          answers: %{
            q.id => %{
              "answer" => nil,
              "is_correct" => false,
              "flagged" => true,
              "time_spent_seconds" => 30
            }
          },
          section_scores: %{"Verbal" => %{"correct" => 0, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "flagged for review but left unanswered"
    end

    test "shows practice weak sections button when weak sections exist", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)

      # A section with < 70% correct is a weak section
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [],
          section_boundaries: [
            %{
              "name" => "Math",
              "question_count" => 0,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 5,
          score_pct: 20.0,
          answers: %{},
          section_scores: %{"Math" => %{"correct" => 1, "total" => 5}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "Practice Weak Sections"
    end

    test "does not show practice weak sections button when all sections are strong", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)

      # Section with 100% correct and under budget → not weak
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [],
          section_boundaries: [
            %{
              "name" => "Math",
              "question_count" => 0,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 5,
          score_total: 5,
          score_pct: 100.0,
          answers: %{},
          section_scores: %{"Math" => %{"correct" => 5, "total" => 5}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      refute html =~ "Practice Weak Sections"
    end

    test "renders session with nil score_pct as 0%", %{conn: conn, user_role: ur, course: c} do
      now = DateTime.utc_now(:second)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [],
          section_boundaries: [],
          status: "submitted",
          submitted_at: now,
          score_correct: 0,
          score_total: 0,
          score_pct: nil,
          answers: %{}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # score_pct(nil) should render as 0%
      assert html =~ "0%"
    end

    test "renders section with under-budget time status", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      # time_spent 60s vs budget 2700s → ratio < 0.80 → :under
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Writing",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 60
            }
          },
          section_scores: %{"Writing" => %{"correct" => 1, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "under"
    end

    test "renders section with zero budget as on_track", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)

      # section_boundaries with time_budget_seconds = 0 → section_time_status(_, 0) → :on_track
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [],
          section_boundaries: [
            %{
              "name" => "NoTimeBudget",
              "question_count" => 0,
              "time_budget_seconds" => 0,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 0,
          score_total: 0,
          score_pct: 0.0,
          answers: %{},
          section_scores: %{}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "NoTimeBudget"
    end

    test "renders question review items with real questions", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Bio",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 90
            }
          },
          section_scores: %{"Bio" => %{"correct" => 1, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # Question content should appear in the review list
      assert html =~ "powerhouse"
      # The correct checkmark should appear
      assert html =~ "✓"
      # Flagged indicator should NOT appear (flagged: false)
      refute html =~ "Flagged"
      # format_time: 90s = "1m 30s"
      assert html =~ "1m 30s"
    end

    test "renders incorrect and flagged answers in question review", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "Bio",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 0,
          score_total: 1,
          score_pct: 0.0,
          answers: %{
            q.id => %{
              "answer" => "Nucleus",
              "is_correct" => false,
              "flagged" => true,
              "time_spent_seconds" => 120
            }
          },
          section_scores: %{"Bio" => %{"correct" => 0, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # Incorrect marker
      assert html =~ "✗"
      # Flagged indicator
      assert html =~ "Flagged"
    end
  end

  describe "handle_event toggle_question" do
    test "expands and collapses question review", %{conn: conn, user_role: ur, course: c} do
      session = create_completed_session(ur, c)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      render_click(view, "toggle_question", %{"index" => "0"})
      render_click(view, "toggle_question", %{"index" => "0"})

      html = render(view)
      assert html =~ "Results" or html =~ "Score"
    end

    test "expands question detail when clicked and shows explanation", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 60
            }
          },
          section_scores: %{}
        })

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # Initially not expanded
      html_before = render(view)
      refute html_before =~ "produces ATP"

      # Expand question 0
      render_click(view, "toggle_question", %{"index" => "0"})
      html_expanded = render(view)

      # Explanation should now be visible
      assert html_expanded =~ "produces ATP"
      assert html_expanded =~ "Mitochondria"

      # Collapse it again
      render_click(view, "toggle_question", %{"index" => "0"})
      html_collapsed = render(view)
      refute html_collapsed =~ "produces ATP"
    end

    test "expands unanswered question showing 'Not answered'", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [],
          status: "submitted",
          submitted_at: now,
          score_correct: 0,
          score_total: 1,
          score_pct: 0.0,
          answers: %{},
          section_scores: %{}
        })

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      render_click(view, "toggle_question", %{"index" => "0"})
      html = render(view)

      assert html =~ "Not answered"
    end
  end

  describe "handle_event practice_weak" do
    test "navigates to practice page", %{conn: conn, user_role: ur, course: c} do
      session = create_completed_session(ur, c)

      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      result = render_click(view, "practice_weak")

      assert {:error, {:live_redirect, %{to: path}}} = result
      assert path =~ "/courses/#{c.id}/practice"
    end
  end

  describe "section time status edge cases" do
    test "on_track section (ratio 0.80-1.05) shows no over/under label", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      # ratio = 2400/2700 ≈ 0.889 → between 0.80 and 1.05 → :on_track
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -50, :minute),
          question_ids_order: [q.id],
          section_boundaries: [
            %{
              "name" => "OnTrack",
              "question_count" => 1,
              "time_budget_seconds" => 2700,
              "start_index" => 0
            }
          ],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 2400
            }
          },
          section_scores: %{"OnTrack" => %{"correct" => 1, "total" => 1}}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      assert html =~ "OnTrack"
      # on_track renders no label text for "over" or "under" beside the time
      refute html =~ ">over<"
      refute html =~ ">under<"
    end

    test "format_time with exact minutes (no seconds remainder) shows only minutes", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      now = DateTime.utc_now(:second)
      q = create_question(c)

      # time_spent_seconds = 120 → 2m (rem 0 → "2m" not "2m 0s")
      {:ok, session} =
        ExamSimulations.create_session(%{
          user_role_id: ur.id,
          course_id: c.id,
          time_limit_seconds: 2700,
          started_at: DateTime.add(now, -45, :minute),
          question_ids_order: [q.id],
          section_boundaries: [],
          status: "submitted",
          submitted_at: now,
          score_correct: 1,
          score_total: 1,
          score_pct: 100.0,
          answers: %{
            q.id => %{
              "answer" => "Mitochondria",
              "is_correct" => true,
              "flagged" => false,
              "time_spent_seconds" => 120
            }
          },
          section_scores: %{}
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{c.id}/exam-simulation/results/#{session.id}")

      # Should show "2m" not "2m 0s"
      assert html =~ "2m"
      refute html =~ "2m 0s"
    end
  end
end
