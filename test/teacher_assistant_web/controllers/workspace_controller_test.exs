defmodule TeacherAssistantWeb.WorkspaceControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  test "selecting a workspace while signed out redirects to sign-in", %{conn: _conn} do
    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> get(~p"/workspaces/select/#{Ecto.UUID.generate()}")

    assert redirected_to(conn) == ~p"/sign-in"
  end
end
