defmodule TeacherAssistantWeb.SchoolLogoController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Accounts

  def show(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Permissions.member?(scope),
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         logo_path when is_binary(logo_path) <- profile.logo_path,
         {:ok, path} <- safe_logo_path(logo_path) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # Resolves the stored relative logo path to an absolute path under the
  # configured uploads dir, refusing anything that would escape it.
  defp safe_logo_path(relative_path) do
    uploads_dir = Application.fetch_env!(:teacher_assistant, :uploads_dir) |> Path.expand()
    path = Path.expand(Path.join(uploads_dir, relative_path))

    if String.starts_with?(path, uploads_dir <> "/") and File.regular?(path) do
      {:ok, path}
    else
      :error
    end
  end
end
