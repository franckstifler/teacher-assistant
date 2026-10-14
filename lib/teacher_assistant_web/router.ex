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
    plug TeacherAssistantWeb.Plug.RequirePasswordChange
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
    get "/verify/bulletin/:token", BulletinVerifyController, :show

    sign_in_route live_view: TeacherAssistantWeb.Auth.SignInLive,
                  register_path: "/register",
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
    get "/school/space/:key", SpaceController, :select

    get "/school/classes/:id/students/:enrollment_id/bulletin/print",
        BulletinPrintController,
        :show

    get "/school/classes/:id/bulletin/print", BulletinPrintController, :class
    get "/school/classes/:id/cards/print", CardPrintController, :show
    get "/school/councils/:class_id/print", CouncilPrintController, :show
    get "/school/classes/:id/timetable/print", TimetablePrintController, :class
    get "/school/timetable/me/print", TimetablePrintController, :me
    get "/school/logo", SchoolLogoController, :show
    get "/school/students/:id/photo", StudentPhotoController, :show
    get "/school/bulletins/:publication_id/photo/:student_id", StudentPhotoController, :frozen
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
        {TeacherAssistantWeb.LiveUserAuth, :assign_space},
        {TeacherAssistantWeb.NotificationHooks, :default},
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
        {TeacherAssistantWeb.LiveUserAuth, :assign_space},
        {TeacherAssistantWeb.NotificationHooks, :default},
        {TeacherAssistantWeb.LiveUserAuth, :require_school_setup}
      ] do
      live "/school", School.DashboardLive, :index
      live "/school/courses", School.CoursesLive, :index
      live "/school/classes", School.ClassesLive, :index
      live "/school/classes/:id", School.ClassLive, :show
      live "/school/classes/:id/photos", School.ClassPhotosLive, :index
      live "/school/classes/:id/teachings", School.TeachingsLive, :show
      live "/school/classes/:id/results", School.ResultsLive, :index
      live "/school/classes/:id/timetable", School.TimetableLive, :show
      live "/school/classes/:id/attendance/:period_id", School.AttendanceLive, :show
      live "/school/classes/:id/register", School.RegisterLive, :show
      live "/school/classes/:id/discipline", School.DisciplineLive, :show
      live "/school/classes/:id/fees", School.FeesLive, :show
      live "/school/timetable", School.TimetableEditorLive, :index
      live "/school/timetable/me", School.MyTimetableLive, :index
      live "/school/today", School.MyDayLive, :index
      live "/school/day", School.DayLive, :index
      live "/school/absences", School.AbsencesLive, :index
      live "/school/conduct", School.ConductLive, :index
      live "/school/sanctions", School.SanctionsLive, :index
      live "/school/students", School.StudentsLive, :index
      live "/school/students/:id", School.StudentLive, :show

      live "/school/classes/:id/students/:enrollment_id/bulletin",
           School.BulletinLive,
           :show

      live "/school/classes/:id/import", School.EnrollImportLive, :new
      live "/school/members", School.MembersLive, :index
      live "/school/settings", School.SettingsLive, :index
      live "/school/settings/profile", School.SettingsLive, :profile
      live "/school/settings/year", School.SettingsLive, :year
      live "/school/settings/subjects", School.SettingsLive, :subjects
      live "/school/settings/coefficients", School.CoefficientsLive, :index
      live "/school/settings/evaluations", School.EvaluationsLive, :index
      live "/school/settings/appreciations", School.AppreciationsLive, :index
      live "/school/settings/passage", School.PassageLive, :index
      live "/school/settings/header", School.OfficialHeaderLive, :index
      live "/school/settings/roles", School.RolesLive, :index
      live "/school/settings/school-life", School.SchoolLifeSettingsLive, :index
      live "/school/settings/new-year", School.NewYearLive, :index
      live "/school/years/:id", School.YearLive, :show
      live "/school/settings/bulletin", School.BulletinTemplateLive, :index
      live "/school/settings/holidays", School.HolidaysLive, :index
      live "/school/settings/assignments", School.AssignmentsLive, :index
      live "/school/periods", School.PeriodsLive, :index
      live "/school/sequences", School.SequenceTrackingLive, :index
      live "/school/bulletins", School.BulletinsLive, :index
      live "/school/councils", School.CouncilsLive, :index
      live "/school/councils/:class_id", School.CouncilLive, :show
      live "/school/corrections", School.CorrectionsLive, :index
      live "/school/corrections/new", School.CorrectionsLive, :new
      live "/school/corrections/review", School.CorrectionReviewLive, :index
      live "/school/notifications", School.NotificationsLive, :index
      live "/school/setup", Onboarding.SetupWizardLive, :index
    end

    ash_authentication_live_session :onboarding,
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/schools/new", Onboarding.CreateSchoolLive
    end

    # The forced first-sign-in password change (spec 2026-10-07), in the paper
    # auth shell: the one screen the `must_change_password` gate lets through.
    ash_authentication_live_session :account,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      layout: {TeacherAssistantWeb.Layouts, :auth},
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/account/password", Account.PasswordLive
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
