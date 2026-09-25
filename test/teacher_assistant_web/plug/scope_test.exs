defmodule TeacherAssistantWeb.Plug.ScopeTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistantWeb.Plug.Scope, as: ScopePlug

  defp run(conn), do: conn |> Plug.Conn.fetch_session() |> ScopePlug.call(ScopePlug.init([]))

  test "assigns the member's school scope", %{conn: conn} do
    {:ok, result} = register_and_log_in_user(%{conn: conn})
    %{conn: conn, workspace: ws, actor: head} = Map.new(result)
    conn = run(conn)

    assert conn.assigns.current_user.id == head.id
    assert conn.assigns.current_scope.current_workspace.id == ws.id
  end

  test "a signed-out request gets an empty scope", %{conn: conn} do
    conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> run()

    assert conn.assigns.current_user == nil
    assert conn.assigns.current_scope == %TeacherAssistant.Scope{locale: "fr"}
  end

  test "a non-member keeps a user-only scope", %{conn: conn} do
    %{workspace: ws} = TeacherAssistant.TeacherFixtures.school_fixture()
    outsider = TeacherAssistant.TeacherFixtures.user_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{user_id: outsider.id, workspace_id: ws.id})
      |> run()

    assert conn.assigns.current_scope.current_user.id == outsider.id
    assert conn.assigns.current_scope.current_workspace == nil
  end
end
