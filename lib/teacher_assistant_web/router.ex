defmodule TeacherAssistantWeb.Router do
  use TeacherAssistantWeb, :router

  use AshAuthentication.Phoenix.Router
  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TeacherAssistantWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug TeacherAssistantWeb.Plug.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :school do
    plug TeacherAssistantWeb.Plug.Scope
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/schools/start", PageController, :start_school
    auth_routes AuthController, TeacherAssistant.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    get "/locale/:locale", LocaleController, :set

    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  layout: {TeacherAssistantWeb.Layouts, :auth},
                  on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    TeacherAssistantWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    reset_route auth_routes_prefix: "/auth",
                layout: {TeacherAssistantWeb.Layouts, :auth},
                overrides: [
                  TeacherAssistantWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    magic_sign_in_route(TeacherAssistant.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      layout: {TeacherAssistantWeb.Layouts, :auth},
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  scope "/", TeacherAssistantWeb do
    pipe_through [:browser, :school]

    get "/workspaces/select/:id", WorkspaceController, :select
    get "/teacher/select-context/:id", TeacherContextController, :select

    get "/school/classes/:id/students/:enrollment_id/bulletin/print",
        BulletinPrintController,
        :show

    get "/school/classes/:id/bulletin/print", BulletinPrintController, :class
    get "/school/classes/:id/timetable/print", TimetablePrintController, :class
    get "/school/timetable/me/print", TimetablePrintController, :me
    get "/school/logo", SchoolLogoController, :show
    get "/schools/invitations/:token", SchoolInvitationController, :show
    post "/schools/invitations/:token/accept", SchoolInvitationController, :accept
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    ash_authentication_live_session :teaching,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :assign_capabilities},
        {TeacherAssistantWeb.LiveUserAuth, :require_teaching_scope}
      ] do
      live "/teacher/contexts/:id/roster", Teacher.RosterLive, :index
      live "/teacher/contexts/:id/marks", Teacher.MarksLive, :index
      live "/teacher/contexts/:id/marks/summary", Teacher.MarksSummaryLive, :index
    end

    ash_authentication_live_session :school_workspace,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :assign_capabilities},
        {TeacherAssistantWeb.LiveUserAuth, :require_school_setup}
      ] do
      live "/school", School.DashboardLive, :index
      live "/school/courses", School.CoursesLive, :index
      live "/school/classes", School.ClassesLive, :index
      live "/school/classes/:id", School.ClassLive, :show
      live "/school/classes/:id/results", School.ResultsLive, :index
      live "/school/classes/:id/timetable", School.TimetableLive, :show
      live "/school/classes/:id/attendance/:period_id", School.AttendanceLive, :show
      live "/school/classes/:id/register", School.RegisterLive, :show
      live "/school/classes/:id/discipline", School.DisciplineLive, :show
      live "/school/classes/:id/fees", School.FeesLive, :show
      live "/school/timetable/me", School.MyTimetableLive, :index

      live "/school/classes/:id/students/:enrollment_id/bulletin",
           School.BulletinLive,
           :show

      live "/school/classes/:id/import", School.EnrollImportLive, :new
      live "/school/members", School.MembersLive, :index
      live "/school/settings", School.SettingsLive, :index
      live "/school/settings/coefficients", School.CoefficientsLive, :index
      live "/school/periods", School.PeriodsLive, :index
      live "/school/setup", Onboarding.SetupWizardLive, :index
    end

    ash_authentication_live_session :onboarding,
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/schools/new", Onboarding.CreateSchoolLive
    end

    ash_authentication_live_session :operator,
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_operator}
      ] do
      live "/admin/schools", Admin.SchoolsLive
    end
  end

  if Application.compile_env(:teacher_assistant, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TeacherAssistantWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
