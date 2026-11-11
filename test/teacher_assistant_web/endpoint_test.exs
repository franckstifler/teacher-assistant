defmodule TeacherAssistantWeb.EndpointTest do
  use TeacherAssistantWeb.ConnCase, async: true

  test "the session cookie is encrypted, not only signed (A6)" do
    opts = TeacherAssistantWeb.Endpoint.session_options()
    assert is_binary(opts[:encryption_salt])
    assert byte_size(opts[:encryption_salt]) >= 8
  end

  test "the LiveDashboard request logger is not plugged without dev routes (A6)", %{conn: conn} do
    conn = get(conn, ~p"/sign-in?request_logger=x")
    refute Map.has_key?(conn.private, :phoenix_request_logger)
  end
end
