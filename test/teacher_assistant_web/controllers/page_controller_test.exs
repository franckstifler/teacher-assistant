defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Teacher Assistant"
    assert html_response(conn, 200) =~ ~s(id="landing-hero")
    assert html_response(conn, 200) =~ ~s(id="product-proof")
    assert html_response(conn, 200) =~ ~s(id="workflow-index")
  end
end
