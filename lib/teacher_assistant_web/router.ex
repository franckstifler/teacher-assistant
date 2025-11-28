defmodule TeacherAssistantWeb.Router do
  use TeacherAssistantWeb, :router

  import Oban.Web.Router
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
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {TeacherAssistantWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {TeacherAssistantWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {TeacherAssistantWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, TeacherAssistant.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    TeacherAssistantWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  TeacherAssistantWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route TeacherAssistant.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(TeacherAssistant.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        TeacherAssistantWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    live_session :configurations,
      on_mount: {TeacherAssistantWeb.LiveUserAuth, :live_user_optional} do
      scope "/configurations" do
        live "/academic_years", Configurations.AcademicYearLive.Index, :index
        live "/academic_years/new", Configurations.AcademicYearLive.Form, :new
        live "/academic_years/:id", Configurations.AcademicYearLive.Show, :show
        live "/academic_years/:id/edit", Configurations.AcademicYearLive.Form, :edit

        live "/classrooms/:id/teachers_and_subjects",
             Configurations.AcademicYearLive.TeacherSubjectForm,
             :teachers_and_subjects

        live "/academic_years/:id/manage_classrooms",
             Configurations.AcademicYearLive.ClassRoomForm,
             :edit_classrooms

        scope "/academic_years/:id" do
          live "/terms/:term_id", Configurations.TermLive.Show, :show
          live "/terms/:term_id/edit", Configurations.TermLive.Form, :edit
        end

        live "/levels", Configurations.LevelLive.Index, :index
        live "/levels/new", Configurations.LevelLive.Form, :new
        live "/levels/:id", Configurations.LevelLive.Show, :show
        live "/levels/:id/edit", Configurations.LevelLive.Form, :edit

        live "/options", Configurations.OptionLive.Index, :index
        live "/options/new", Configurations.OptionLive.Form, :new
        live "/options/:id", Configurations.OptionLive.Show, :show
        live "/options/:id/edit", Configurations.OptionLive.Form, :edit

        live "/levels_options", Configurations.LevelOptionLive.Index, :index
        live "/levels_options/:id", Configurations.LevelOptionLive.Show, :show

        live "/levels_options/:id/manage_subjects",
             Configurations.LevelOptionLive.ManageSubjectForm,
             :edit_subjects

        live "/subjects", Configurations.SubjectLive.Index, :index
        live "/subjects/new", Configurations.SubjectLive.Form, :new
        live "/subjects/:id", Configurations.SubjectLive.Show, :show
        live "/subjects/:id/edit", Configurations.SubjectLive.Form, :edit
      end
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TeacherAssistantWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:teacher_assistant, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TeacherAssistantWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end
end
