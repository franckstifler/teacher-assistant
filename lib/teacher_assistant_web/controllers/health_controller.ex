defmodule TeacherAssistantWeb.HealthController do
  @moduledoc """
  `GET /health` for the uptime check (spec audit follow-ups A1): `200 {"status":"ok"}`
  when the database answers `SELECT 1`, `503 {"status":"error"}` otherwise. No session,
  no authentication, nothing else in the body.
  """
  use TeacherAssistantWeb, :controller

  def show(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Ecto.Adapters.SQL.query(TeacherAssistant.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(503) |> json(%{status: "error"})
    end
  end
end
