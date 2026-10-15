defmodule TeacherAssistantWeb.SchoolLogoController do
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.Accounts

  def show(conn, params) do
    field =
      case params["kind"] do
        "signature" -> :signature_path
        "stamp" -> :stamp_path
        _ -> :logo_path
      end

    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         stored when is_binary(stored) <- Map.fetch!(profile, field),
         {:ok, path} <- TeacherAssistant.Uploads.resolve(stored) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end
end
