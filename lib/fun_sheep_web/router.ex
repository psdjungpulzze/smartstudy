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

  scope "/", FunSheepWeb do
    pipe_through :browser

    live "/", LoginLive, :index
    live "/register", RegisterLive, :index
  end

  # OAuth callback routes (regular controller, not LiveView)
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
      live "/profile/setup", ProfileSetupLive, :index
      live "/parent", ParentDashboardLive, :index
      live "/teacher", TeacherDashboardLive, :index
      live "/guardians", GuardianInviteLive, :index

      live "/courses", CourseSearchLive, :index
      live "/courses/new", CourseNewLive, :new
      live "/courses/:id/edit", CourseNewLive, :edit
      live "/courses/:id", CourseDetailLive, :show
      live "/courses/:course_id/questions", QuestionBankLive, :index
      live "/courses/:course_id/practice", PracticeLive, :index

      live "/quick-test", QuickTestLive, :index

      live "/tests", TestScheduleLive, :index
      live "/tests/new", TestScheduleNewLive, :new
      live "/tests/:schedule_id/assess", AssessmentLive, :show
      live "/tests/:schedule_id/readiness", ReadinessDashboardLive, :show
      live "/tests/:schedule_id/format", TestFormatLive, :show
      live "/tests/:schedule_id/format-test", FormatTestLive, :show

      live "/study-guides", StudyGuidesListLive, :index
      live "/study-guides/:id", StudyGuideLive, :show
    end
  end

  # Export routes (file downloads, outside live_session)
  scope "/export", FunSheepWeb do
    pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

    get "/study-guide/:id", ExportController, :study_guide
    get "/readiness/:schedule_id", ExportController, :readiness_report
  end

  # Admin LiveView routes
  live_session :admin,
    layout: {FunSheepWeb.Layouts, :app},
    on_mount: [{FunSheepWeb.LiveHelpers, :require_admin}] do
    scope "/admin", FunSheepWeb do
      pipe_through [:browser, FunSheepWeb.Plugs.DevAuth]

      live "/", AdminDashboardLive, :index
    end
  end

  # Interactor webhook and tool callback routes (no auth required)
  scope "/api/webhooks", FunSheepWeb do
    pipe_through :api

    post "/interactor", WebhookController, :interactor
    post "/agent-tools", WebhookController, :tool_callback
  end

  # Dev-only routes (login bypass)
  if Application.compile_env(:fun_sheep, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev", FunSheepWeb do
      pipe_through :browser

      live "/login", DevLoginLive, :index
      post "/auth", DevAuthController, :create
      delete "/auth", DevAuthController, :delete
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/live-dashboard", metrics: FunSheepWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
