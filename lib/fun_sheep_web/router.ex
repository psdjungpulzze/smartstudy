defmodule FunSheepWeb.Router do
  use FunSheepWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FunSheepWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Mobile app REST API — Bearer token auth, versioned under /api/v1
  pipeline :mobile_api do
    plug :accepts, ["json"]
    plug FunSheepWeb.Plugs.ApiAuth
  end

  # Dev-only binary upload receiver. Needs session (for DevAuth) but no CSRF
  # — the URL-embedded HMAC token is the auth mechanism for this endpoint.
  pipeline :local_upload do
    plug :fetch_session
  end

  # Health check for Cloud Run (no auth, no CSRF)
  scope "/health", FunSheepWeb do
    pipe_through :api
    get "/", HealthController, :index
  end

  scope "/", FunSheepWeb do
    pipe_through :browser

    get "/", AuthController, :root
    get "/register", AuthController, :register
  end

  # Public auth LiveView routes (login/register/password recovery)
  live_session :public_auth, layout: false do
    scope "/auth", FunSheepWeb do
      pipe_through :browser

      live "/login", LoginLive, :index
      live "/register", RegisterLive, :index
      live "/forgot-password", ForgotPasswordLive, :index
      live "/reset-password/:token", ResetPasswordLive, :index
    end

    # Hidden admin login: same LoginLive without role chips. Admin role is
    # derived server-side from the Interactor profile's `metadata.role`
    # claim — a non-admin logging in here just ends up on /dashboard.
    scope "/admin", FunSheepWeb do
      pipe_through :browser

      live "/login", LoginLive, :admin
    end
  end

  # OAuth callback and session routes (regular controller, not LiveView)
  scope "/auth", FunSheepWeb do
    pipe_through :browser

    get "/login/redirect", AuthController, :login
    get "/callback", AuthController, :callback
    get "/session", AuthController, :session
    post "/logout", AuthController, :logout
  end

  # Authenticated LiveView routes
  live_session :authenticated,
    layout: {FunSheepWeb.Layouts, :app},
    on_mount: [{FunSheepWeb.LiveHelpers, :require_auth}] do
    scope "/", FunSheepWeb do
      pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

      live "/dashboard", DashboardLive, :index
      live "/practice", QuickPracticeLive, :index
      live "/profile/setup", ProfileSetupLive, :index
      live "/parent", ParentDashboardLive, :index
      live "/parent/settings", ParentSettingsLive, :index
      live "/teacher", TeacherDashboardLive, :index
      live "/guardians", GuardianInviteLive, :index

      # Email-only student→guardian invite claim
      live "/guardian-invite/:token", GuardianInviteClaimLive, :show

      # Flow B (§5.2) — parent onboarding + claim-code redemption
      live "/onboarding/parent", ParentOnboardingLive, :index
      live "/claim/:code", ClaimCodeLive, :show

      # Flow A (§5.1) — student onboarding
      live "/onboarding/student", StudentOnboardingLive, :index

      # Flow C (§6.2) — teacher onboarding
      live "/onboarding/teacher", TeacherOnboardingLive, :index

      live "/subscription", SubscriptionLive, :index
      live "/leaderboard", LeaderboardLive, :index

      live "/social/profile/:id", UserProfileLive, :show
      live "/social/find", FindFriendsLive, :index

      live "/integrations", IntegrationsLive, :index

      live "/catalog", CatalogLive, :index
      live "/courses", CourseSearchLive, :index
      live "/courses/new", CourseNewLive, :new
      live "/courses/:id/edit", CourseNewLive, :edit
      live "/courses/:id", CourseDetailLive, :show
      live "/courses/:course_id/questions", QuestionBankLive, :index
      live "/courses/:course_id/practice", PracticeLive, :index
      live "/courses/:course_id/quick-test", QuickTestLive, :index
      live "/courses/:course_id/daily-shear", DailyChallengeLive, :index
      live "/courses/:course_id/review", ReviewLive, :index

      live "/courses/:course_id/tests", TestScheduleLive, :index
      live "/courses/:course_id/tests/new", TestScheduleNewLive, :new
      live "/courses/:course_id/tests/:schedule_id/edit", TestScheduleNewLive, :edit
      live "/courses/:course_id/tests/:schedule_id/assess", AssessmentLive, :show
      live "/courses/:course_id/tests/:schedule_id/readiness", ReadinessDashboardLive, :show
      live "/courses/:course_id/tests/:schedule_id/format", TestFormatLive, :show
      live "/courses/:course_id/tests/:schedule_id/format-test", FormatTestLive, :show

      # Exam Simulation
      live "/courses/:course_id/exam-simulation", ExamSimulationLive.Index, :index
      live "/courses/:course_id/exam-simulation/exam", ExamSimulationLive.Exam, :exam

      live "/courses/:course_id/exam-simulation/results/:session_id",
           ExamSimulationLive.Results,
           :results

      live "/courses/:course_id/essay/:question_id", EssayLive, :index
      live "/courses/:course_id/memory-span", MemorySpanLive, :index
      live "/courses/:course_id/study/:section_id", StudyHubLive, :show

      live "/courses/:course_id/study-guides", StudyGuidesListLive, :index
      live "/courses/:course_id/study-guides/:id", StudyGuideLive, :show

      # Custom fixed-question tests
      live "/custom-tests", FixedTests.BankLive, :index
      live "/custom-tests/new", FixedTests.BankLive, :new
      live "/custom-tests/:id", FixedTests.BankLive, :show
      live "/custom-tests/:id/start", FixedTests.StartLive, :start
      live "/custom-tests/:id/assign", FixedTests.StartLive, :assign
      live "/custom-tests/session/:session_id", FixedTests.SessionLive, :show
    end
  end

  # Integration controller routes (OAuth redirect + callback + disconnect)
  scope "/integrations", FunSheepWeb do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

    get "/connect/:provider", IntegrationController, :connect
    get "/callback", IntegrationController, :callback
    post "/:id/sync", IntegrationController, :sync_now
    delete "/:id", IntegrationController, :disconnect
  end

  # File upload endpoint (direct HTTP, not LiveView)
  scope "/api", FunSheepWeb do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

    post "/upload", UploadController, :create

    # Direct-to-storage (resumable) flow. Clients call sign to get an
    # upload URL, PUT the file body to it, then call finalize. This keeps
    # the web tier out of the upload path so 200-500 MB PDFs don't hit
    # Cloud Run's ingress limit or the BEAM heap.
    post "/uploads/sign", UploadController, :sign
    post "/uploads/finalize", UploadController, :finalize
  end

  # Local-backend PUT receiver — only active when storage_backend is
  # FunSheep.Storage.Local (dev/test). Uses a minimal pipeline with no CSRF
  # protection; the HMAC token embedded in the URL is the auth mechanism.
  scope "/api", FunSheepWeb do
    pipe_through [:local_upload, FunSheepWeb.Plugs.DevAuth]
    put "/uploads/local/:token/*key", UploadController, :local_put
  end

  # Export routes (file downloads, outside live_session)
  scope "/export", FunSheepWeb do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

    get "/study-guide/:id", ExportController, :study_guide
    get "/readiness/:schedule_id", ExportController, :readiness_report
  end

  # Admin LiveView routes
  import Oban.Web.Router

  live_session :admin,
    layout: {FunSheepWeb.Layouts, :app},
    on_mount: [{FunSheepWeb.LiveHelpers, :require_admin}] do
    scope "/admin", FunSheepWeb do
      pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

      live "/", AdminDashboardLive, :index
      live "/users", AdminUsersLive, :index
      live "/users/:id", AdminUserDetailLive, :show
      live "/courses", AdminCoursesLive, :index
      live "/courses/:id", AdminCourseShowLive, :show
      live "/courses/:id/sections", AdminCourseSectionsLive, :index
      live "/materials", AdminMaterialsLive, :index
      live "/source-health", AdminSourceHealthLive, :index
      live "/web-pipeline", AdminWebPipelineLive, :index
      live "/questions/review", AdminQuestionReviewLive, :index
      live "/audit-log", AdminAuditLogLive, :index
      live "/settings/mfa", AdminMfaSettingsLive, :index
      live "/usage/ai", AdminAIUsageLive, :index
      live "/jobs/failures", AdminJobsLive, :index
      live "/flags", AdminFlagsLive, :index
      live "/interactor/agents", AdminInteractorAgentsLive, :index
      live "/interactor/profiles", AdminInteractorProfilesLive, :index
      live "/interactor/credentials", AdminInteractorCredentialsLive, :index
      live "/billing", AdminBillingLive, :index
      live "/geo", AdminGeoLive, :index
      live "/health", AdminHealthLive, :index
      live "/course-builder", AdminTestCourseBuilderLive, :index
      live "/source-registry", AdminSourceRegistryLive, :index
    end
  end

  # Admin controller routes (impersonation start/stop) — plug-guarded.
  scope "/admin", FunSheepWeb do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth, FunSheepWeb.Plugs.RequireAdmin]

    post "/impersonate/:user_id", AdminImpersonationController, :create
    delete "/impersonate", AdminImpersonationController, :delete
  end

  # Oban Web dashboard — lives in its own live_session (the macro manages it),
  # so we guard via a plug pipeline rather than an on_mount hook.
  scope "/admin" do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth, FunSheepWeb.Plugs.RequireAdmin]

    oban_dashboard("/jobs")
  end

  # Public proof card sharing (no auth required)
  scope "/share", FunSheepWeb do
    pipe_through :browser

    live "/progress/:token", ProofCardLive, :show
  end

  # Public unsubscribe (signed token — no auth required, spec §8.4)
  scope "/notifications", FunSheepWeb do
    pipe_through :browser

    get "/unsubscribe/:token", NotificationUnsubscribeController, :show
  end

  # Interactor webhook and tool callback routes (no auth required)
  scope "/api/webhooks", FunSheepWeb do
    pipe_through :api

    post "/interactor", WebhookController, :interactor
    post "/agent-tools", WebhookController, :tool_callback
  end

  # ── Mobile REST API v1 ──────────────────────────────────────────────────────
  #
  # Auth routes — no Bearer token required (these issue the token)
  scope "/api/v1/auth", FunSheepWeb.API.V1 do
    pipe_through :api

    get "/authorize_url", AuthController, :authorize_url
    post "/token", AuthController, :token
    post "/refresh", AuthController, :refresh
  end

  # Authenticated mobile API routes — require Bearer token
  scope "/api/v1", FunSheepWeb.API.V1 do
    pipe_through :mobile_api

    # Current user
    get "/users/me", UsersController, :me
    put "/users/me", UsersController, :update

    # Enrolled courses
    get "/courses", CoursesController, :index
    get "/courses/:id", CoursesController, :show

    # Practice
    get "/courses/:course_id/practice/questions", PracticeController, :questions
    post "/practice/answers", PracticeController, :record_answers

    # Notifications
    get "/notifications", NotificationsController, :index
    post "/notifications/:id/read", NotificationsController, :mark_read
    post "/notifications/read-all", NotificationsController, :mark_all_read
    post "/notifications/push_tokens", NotificationsController, :register_token
    delete "/notifications/push_tokens/:token", NotificationsController, :deactivate_token
  end

  # Dev-only routes (login bypass)
  if Application.compile_env(:fun_sheep, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev", FunSheepWeb do
      pipe_through :browser

      live "/login", DevLoginLive, :index
      post "/auth", DevAuthController, :create
      delete "/auth", DevAuthController, :delete
      get "/progress/broadcast", DevProgressController, :broadcast
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/live-dashboard", metrics: FunSheepWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
