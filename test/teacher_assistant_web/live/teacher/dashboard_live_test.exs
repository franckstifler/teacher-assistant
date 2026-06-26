defmodule TeacherAssistantWeb.Teacher.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "redirects to sign-in when logged out", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/teacher")
  end
end
