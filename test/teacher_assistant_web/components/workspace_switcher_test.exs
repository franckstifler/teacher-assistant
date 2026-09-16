defmodule TeacherAssistantWeb.WorkspaceSwitcherTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "the switcher lists the personal workspace and member schools", %{conn: conn, actor: user} do
    {:ok, _school} = Schools.create_school(user, %{name: "École Deux"})
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "École Deux"
    assert html =~ "id=\"workspace-switcher\""
  end
end
