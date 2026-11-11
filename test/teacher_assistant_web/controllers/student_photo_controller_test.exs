defmodule TeacherAssistantWeb.StudentPhotoControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, st} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, st} = StudentPhotos.store(scope, st, tmp)
    %{scope: scope, cg: cg, st: st}
  end

  defp etag(st), do: ~s("#{Path.basename(st.photo_path, ".jpg")}")

  test "a member gets the current photo with an etag, cached a week (A8)", %{conn: conn, st: st} do
    conn = get(conn, ~p"/school/students/#{st.id}/photo")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
    assert get_resp_header(conn, "cache-control") == ["private, max-age=604800"]
    assert get_resp_header(conn, "etag") == [etag(st)]
    assert conn.resp_body == File.read!("test/support/fixtures/files/1x1.jpg")
  end

  test "a matching If-None-Match answers 304 without a body (A8)", %{conn: conn, st: st} do
    conn =
      conn
      |> put_req_header("if-none-match", etag(st))
      |> get(~p"/school/students/#{st.id}/photo")

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "etag") == [etag(st)]
  end

  test "a different If-None-Match answers 200 with the file (A8)", %{conn: conn, st: st} do
    conn =
      conn
      |> put_req_header("if-none-match", ~s("old-photo"))
      |> get(~p"/school/students/#{st.id}/photo")

    assert conn.status == 200
  end

  test "another school's member gets a 404 even with a matching If-None-Match (A8)", %{st: st} do
    %{head_user: other_head, workspace: other_ws} =
      TeacherFixtures.setup_complete_school_fixture()

    conn =
      build_conn()
      |> log_in_user(other_head)
      |> Plug.Conn.put_session(:workspace_id, other_ws.id)
      |> put_req_header("if-none-match", etag(st))
      |> get(~p"/school/students/#{st.id}/photo")

    assert conn.status == 404
  end

  test "a student without photo is a 404", %{conn: conn, scope: scope, cg: cg} do
    {:ok, other} = Enrollment.add_student(scope, cg, %{full_name: "Ben", sex: :m})
    assert get(conn, ~p"/school/students/#{other.id}/photo").status == 404
  end

  test "another school's member gets a 404", %{st: st} do
    %{head_user: other_head, workspace: other_ws} =
      TeacherFixtures.setup_complete_school_fixture()

    conn =
      build_conn()
      |> log_in_user(other_head)
      |> Plug.Conn.put_session(:workspace_id, other_ws.id)
      |> get(~p"/school/students/#{st.id}/photo")

    assert conn.status == 404
  end
end
