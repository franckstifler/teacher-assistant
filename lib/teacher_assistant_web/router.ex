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
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", TeacherAssistantWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, TeacherAssistant.Accounts.User, path: "/auth"
    sign_out_route AuthController
    get "/workspaces/select/:id", WorkspaceController, :select

    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    TeacherAssistantWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  TeacherAssistantWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

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

    ash_authentication_live_session :teacher_workspace,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/teacher", Teacher.DashboardLive, :index
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
