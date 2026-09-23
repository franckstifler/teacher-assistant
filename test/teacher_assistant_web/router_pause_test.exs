defmodule TeacherAssistantWeb.RouterPauseTest do
  use TeacherAssistantWeb.ConnCase, async: true

  @paused ~w(/teacher /teacher/setup /teacher/import /teacher/log)

  setup :register_and_log_in_user

  # Note: Phoenix.Endpoint.RenderErrors deliberately does NOT reraise
  # Phoenix.Router.NoRouteError (see deps/phoenix/lib/phoenix/endpoint/render_errors.ex,
  # `defp maybe_raise(:error, %NoRouteError{}, _stack), do: :ok`) — an unmatched route
  # always renders as a 404 response instead of raising to the caller. So route absence
  # is asserted via the resulting 404 status rather than `assert_raise`.
  test "teacher-personal routes are absent", %{conn: conn} do
    for path <- @paused do
      conn = get(conn, path)
      assert conn.status == 404
    end

    id = Ecto.UUID.generate()

    for path <- [
          "/teacher/plans/#{id}",
          "/teacher/plans/#{id}/coverage",
          "/teacher/entries/#{id}/fiche",
          "/teacher/entries/#{id}/fiche/print"
        ] do
      conn = get(conn, path)
      assert conn.status == 404
    end

    conn = post(conn, "/workspaces", %{"school" => %{"name" => "X"}})
    assert conn.status == 404
  end

  test "school teaching routes still resolve", %{conn: conn} do
    id = Ecto.UUID.generate()

    for path <- [
          "/teacher/contexts/#{id}/roster",
          "/teacher/contexts/#{id}/marks",
          "/teacher/contexts/#{id}/marks/summary",
          "/teacher/select-context/#{id}"
        ] do
      # any response other than NoRouteError proves the route exists
      conn = get(conn, path)
      assert conn.status in [200, 302]
    end
  end
end
