defmodule TeacherAssistantWeb.HealthControllerTest do
  use TeacherAssistantWeb.ConnCase

  test "GET /health answers ok as JSON when the database responds", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "GET /health needs no session and sets no cookie", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert get_resp_header(conn, "set-cookie") == []
  end
end
