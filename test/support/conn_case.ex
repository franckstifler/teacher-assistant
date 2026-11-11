defmodule TeacherAssistantWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TeacherAssistantWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TeacherAssistantWeb.Endpoint

      use TeacherAssistantWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TeacherAssistantWeb.ConnCase

      import TeacherAssistant.DataCase,
        only: [school_scope: 2, assert_forbidden: 1, paper_changeset: 4, impersonating: 2]
    end
  end

  setup tags do
    TeacherAssistant.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def log_in_user(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_user_in_session(user)
  end

  @doc """
  Signs `user` into a conn that already has a test session, the way
  `AuthController` does: a stored token (so revoking it signs them out) and
  the live socket id that revocation disconnects.
  """
  def put_user_in_session(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> AshAuthentication.Plug.Helpers.store_in_session(
      Ash.Resource.put_metadata(user, :token, token)
    )
    |> Plug.Conn.put_session(:live_socket_id, TeacherAssistant.Accounts.live_socket_id(user))
  end

  @doc """
  Logs in a fresh user as the head of a fresh, setup-complete school and puts
  the school in the session. The school is verified unless the test is tagged
  `@tag verified: false`. Returns `workspace`, `actor` (the head), `year` and
  the head's `scope`.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    %{workspace: school, head_user: head, year: year, scope: scope} =
      TeacherAssistant.TeacherFixtures.setup_complete_school_fixture(%{
        verified: Map.get(context, :verified, true)
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(head)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, conn: conn, workspace: school, actor: head, year: year, scope: scope}
  end

  def update_nested_form(view, form_selector, trigger_element, position \\ "end") do
    view
    |> Phoenix.LiveViewTest.form(form_selector, %{trigger_element => position})
    |> Phoenix.LiveViewTest.render_change()
  end
end
