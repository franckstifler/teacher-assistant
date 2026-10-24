defmodule TeacherAssistantWeb.WorkspaceControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  test "selecting a workspace while signed out redirects to sign-in", %{conn: _conn} do
    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post(~p"/workspaces/select/#{Ecto.UUID.generate()}")

    assert redirected_to(conn) == ~p"/sign-in"
  end

  test "the session switches take no GET, so another site's link can't fire them", %{
    conn: conn
  } do
    for path <- [
          "/workspaces/select/#{Ecto.UUID.generate()}",
          "/teacher/select-context/#{Ecto.UUID.generate()}",
          "/school/space/enseignant"
        ] do
      assert conn |> get(path) |> response(404)
    end
  end
end
