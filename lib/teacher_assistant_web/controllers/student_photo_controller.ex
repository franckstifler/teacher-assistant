defmodule TeacherAssistantWeb.StudentPhotoController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Enrollment, Uploads}

  @doc "Spec 2026-10-12 §4: the student's current photo, for members of the student's school."
  def show(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, %{photo_path: relative}} when is_binary(relative) <-
           Enrollment.fetch_owned_student(scope, id),
         {:ok, path} <- Uploads.resolve(relative) do
      send_photo(conn, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def send_photo(conn, path) do
    conn
    |> put_resp_content_type("image/jpeg")
    |> put_resp_header("cache-control", "private, max-age=86400")
    |> send_file(200, path)
  end
end
