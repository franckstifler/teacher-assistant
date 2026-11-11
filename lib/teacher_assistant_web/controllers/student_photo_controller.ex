defmodule TeacherAssistantWeb.StudentPhotoController do
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Enrollment, Uploads}
  alias TeacherAssistant.Academics.BulletinPublication

  @doc "Spec 2026-10-12 §4: the student's current photo, for members of the student's school."
  def show(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, %{photo_path: relative}} when is_binary(relative) <-
           Enrollment.fetch_owned_student(scope, id),
         {:ok, path} <- Uploads.resolve(relative, scope.current_workspace.id) do
      send_photo(conn, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  @doc "Spec 2026-10-12 §4: the photo frozen in a published bulletin."
  def frozen(conn, %{"publication_id" => pub_id, "student_id" => student_id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, pub} <- Ash.get(BulletinPublication, pub_id, scope: scope),
         %{student: student} <- Enum.find(pub.snapshot.roster, &(&1.student.id == student_id)),
         {:ok, path} <-
           Uploads.resolve(Map.get(student, :photo_path), scope.current_workspace.id) do
      send_photo(conn, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # A8: a photo file never changes (a new photo is a new file name), so its name is
  # its etag and the browser keeps it a week; a matching `If-None-Match` is a 304.
  # Only reached after the ownership checks above.
  def send_photo(conn, path) do
    etag = ~s("#{Path.basename(path, ".jpg")}")

    conn =
      conn
      |> put_resp_header("cache-control", "private, max-age=604800")
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("image/jpeg")
      |> send_file(200, path)
    end
  end
end
