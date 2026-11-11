defmodule TeacherAssistantWeb.Router do
  use TeacherAssistantWeb, :router

  use AshAuthentication.Phoenix.Router
  import AshAuthentication.Plug.Helpers
  import ErrorTracker.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TeacherAssistantWeb.Layouts, :root}
    plug :protect_from_forgery
    # Security headers and the Content-Security-Policy, with a per-request nonce (A6).
    plug TeacherAssistantWeb.Plug.ContentSecurityPolicy
    # « Rester connecté »: a remember-me cookie signs back in a browser that lost its session.
    plug :sign_in_with_remember_me
    plug :load_from_session
    plug TeacherAssistantWeb.Plug.EndImpersonation
    plug TeacherAssistantWeb.Plug.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :school do
    plug TeacherAssistantWeb.Plug.Scope
    plug TeacherAssistantWeb.Plug.RequirePasswordChange
  end

  # The uptime check: no session, no cookie, no browser pipeline.
  scope "/", TeacherAssistantWeb do
    pipe_through :health

    get "/health", HealthController, :show
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/schools/start", PageController, :start_school
    get "/confidentialite", PageController, :privacy
    auth_routes AuthController, TeacherAssistant.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    get "/locale/:locale", LocaleController, :set
    # The operator acting as a member: these write the session, so POST/DELETE only.
    post "/impersonation", ImpersonationController, :create
    delete "/impersonation", ImpersonationController, :delete
    get "/verify/bulletin/:token", BulletinVerifyController, :show
    get "/verify/card/:token", CardVerifyController, :show
    get "/verify/receipt", ReceiptVerifyController, :lookup
    get "/verify/receipt/:token", ReceiptVerifyController, :show
    get "/verify/note/:token", ReceiptVerifyController, :show_note
    get "/verify/warning/:token", ReceiptVerifyController, :show_warning

    sign_in_route live_view: TeacherAssistantWeb.Auth.SignInLive,
                  register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  layout: {TeacherAssistantWeb.Layouts, :auth},
                  on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_no_user}],
                  gettext_backend: {TeacherAssistantWeb.Gettext, "auth"},
                  overrides: [
                    TeacherAssistantWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    reset_route auth_routes_prefix: "/auth",
                layout: {TeacherAssistantWeb.Layouts, :auth},
                on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_optional}],
                gettext_backend: {TeacherAssistantWeb.Gettext, "auth"},
                overrides: [
                  TeacherAssistantWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    magic_sign_in_route(TeacherAssistant.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      layout: {TeacherAssistantWeb.Layouts, :auth},
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_optional}],
      gettext_backend: {TeacherAssistantWeb.Gettext, "auth"},
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  scope "/", TeacherAssistantWeb do
    pipe_through [:browser, :school]

    # These switches write the session: POST only, so another site can't fire them.
    post "/workspaces/select/:id", WorkspaceController, :select
    post "/teacher/select-context/:id", TeacherContextController, :select
    post "/school/space/:key", SpaceController, :select

    get "/school/classes/:id/students/:enrollment_id/bulletin/print",
        BulletinPrintController,
        :show

    get "/school/classes/:id/bulletin/print", BulletinPrintController, :class
    get "/school/classes/:id/cards/print", CardPrintController, :show
    get "/school/classes/:id/class-list/print", ClassListPrintController, :roster
    get "/school/classes/:id/class-list/working/print", ClassListPrintController, :working
    get "/teacher/contexts/:id/class-list/print", ClassListPrintController, :teacher
    get "/teacher/class-lists/print", ClassListPrintController, :teacher_all
    get "/school/councils/:class_id/print", CouncilPrintController, :show
    get "/school/classes/:id/timetable/print", TimetablePrintController, :class
    get "/school/timetable/me/print", TimetablePrintController, :me
    get "/school/timetable/teachers/print", TimetablePrintController, :teachers
    get "/school/timetable/general/print", TimetablePrintController, :general
    get "/school/classes/:id/roll-sheet/print", RollSheetPrintController, :class
    get "/school/roll-sheets/print", RollSheetPrintController, :all
    get "/school/classes/:id/mark-sheet/print", MarkSheetPrintController, :class
    get "/school/mark-sheets/print", MarkSheetPrintController, :all
    get "/school/statistics/me/print", StatisticsPrintController, :show
    get "/school/fees/receipts/:id/print", ReceiptPrintController, :show
    get "/school/fees/notes/:id/print", FeePaperPrintController, :note
    get "/school/fees/warnings/print", FeePaperPrintController, :warnings
    get "/school/classes/:id/fees/control/print", FeePaperPrintController, :control
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
        {TeacherAssistantWeb.LiveUserAuth, :require_active_school},
        {TeacherAssistantWeb.LiveUserAuth, :require_module},
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
        {TeacherAssistantWeb.LiveUserAuth, :require_active_school},
        {TeacherAssistantWeb.LiveUserAuth, :require_module},
        {TeacherAssistantWeb.LiveUserAuth, :assign_capabilities},
        {TeacherAssistantWeb.LiveUserAuth, :assign_space},
        {TeacherAssistantWeb.NotificationHooks, :default},
        {TeacherAssistantWeb.LiveUserAuth, :require_school_setup}
      ] do
      live "/school", School.DashboardLive, :index
      live "/school/courses", School.CoursesLive, :index
      live "/school/statistics/me", Teacher.StatisticsLive, :index
      live "/school/classes", School.ClassesLive, :index
      live "/school/classes/:id", School.ClassOverviewLive, :show
      live "/school/classes/:id/students", School.ClassLive, :show
      live "/school/classes/:id/photos", School.ClassPhotosLive, :index
      live "/school/exam-photos", School.ExamPhotosLive, :index
      live "/school/classes/:id/teachings", School.TeachingsLive, :show
      live "/school/classes/:id/results", School.ResultsLive, :index
      live "/school/classes/:id/timetable", School.TimetableLive, :show
      live "/school/classes/:id/attendance/:period_id", School.AttendanceLive, :show
      live "/school/classes/:id/register", School.RegisterLive, :show
      live "/school/classes/:id/roll-sheet", School.RollSheetLive, :show
      live "/school/classes/:id/discipline", School.DisciplineLive, :show
      live "/school/classes/:id/absence-hours", School.AbsenceHoursLive, :show
      live "/school/classes/:id/fees", School.FeesLive, :show
      live "/school/classes/:id/fees/control", School.FeeControlLive, :show
      live "/school/fees", School.FeesOverviewLive, :index
      live "/school/timetable", School.TimetableEditorLive, :index
      live "/school/timetable/me", School.MyTimetableLive, :index
      live "/school/timetable/availability", School.AvailabilityLive, :index
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
      live "/school/settings/rooms", School.RoomsLive, :index
      live "/school/settings/fees", School.FeeSettingsLive, :index
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

    # Operator console spec §2: outside :school_workspace, so it is not itself refused.
    ash_authentication_live_session :suspended,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/school/suspended", School.SuspendedLive
    end

    ash_authentication_live_session :operator,
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_operator}
      ] do
      live "/admin", Admin.OverviewLive
      live "/admin/schools", Admin.SchoolsLive
      live "/admin/schools/:id", Admin.SchoolLive
      live "/admin/users", Admin.UsersLive
      live "/admin/journal", Admin.JournalLive
    end

    # ErrorTracker's own screens, in their own live_session and layout; the same
    # guards as the console: signed in (from the session cookie), then operator only.
    error_tracker_dashboard("/admin/errors",
      csp_nonce_assign_key: :csp_nonce,
      on_mount: [
        AshAuthentication.Phoenix.LiveSession,
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_operator}
      ]
    )
  end

  if Application.compile_env(:teacher_assistant, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: TeacherAssistantWeb.Telemetry,
        csp_nonce_assign_key: :csp_nonce

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end
  end
end
