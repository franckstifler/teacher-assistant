defmodule TeacherAssistantWeb.School.ClassPhotosLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  @jpeg "test/support/fixtures/files/1x1.jpg"

  setup do
    %{scope: scope, year: year, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben Ateba", sex: :m})
    {:ok, other_cg} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, outsider} = Enrollment.add_student(scope, other_cg, %{full_name: "Zoe", sex: :f})
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    %{scope: scope, ws: ws, cg: cg, awa: awa, ben: ben, outsider: outsider, sg: sg}
  end

  defp conn_for(scope, ws),
    do:
      build_conn()
      |> log_in_user(scope.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

  defp upload(view, name) do
    input =
      file_input(view, "#photo-upload-form", :photo, [
        %{name: name, content: File.read!(@jpeg), type: "image/jpeg"}
      ])

    render_upload(input, name)
  end

  test "the SG uploads a photo for a student of the class", %{sg: sg, ws: ws, cg: cg, awa: awa} do
    {:ok, view, html} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    assert html =~ "0/2"

    upload(view, "#{awa.id}.jpg")

    assert {:ok, %{photo_path: path}} = Enrollment.fetch_owned_student(sg, awa.id)
    assert is_binary(path)
    assert view |> element("#photo-count") |> render() =~ "1/2"
    assert_push_event(view, "photo:stored", %{student_id: student_id})
    assert student_id == awa.id
  end

  test "a file named after a student of another class is refused",
       %{sg: sg, ws: ws, cg: cg, outsider: outsider} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    html = upload(view, "#{outsider.id}.jpg")

    assert html =~ "pas dans cette classe"
    assert {:ok, %{photo_path: nil}} = Enrollment.fetch_owned_student(sg, outsider.id)
  end

  test "filter and delete with in-page confirmation", %{
    sg: sg,
    ws: ws,
    cg: cg,
    awa: awa,
    ben: ben
  } do
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!(@jpeg, tmp)
    {:ok, _} = StudentPhotos.store(sg, awa, tmp)

    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/photos")
    view |> element("#only-missing") |> render_click()
    refute has_element?(view, "#photo-#{awa.id}")
    assert has_element?(view, "#photo-#{ben.id}")
    view |> element("#only-missing") |> render_click()

    view |> element("#photo-#{awa.id} button") |> render_click()
    view |> element("#remove-photo") |> render_click()
    view |> element("#confirm-remove-photo") |> render_click()

    assert {:ok, %{photo_path: nil}} = Enrollment.fetch_owned_student(sg, awa.id)
    assert view |> element("#photo-count") |> render() =~ "0/2"
  end

  test "a teacher is sent away and sees no Photos link", %{scope: scope, ws: ws, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.current_user.id)
    conn = conn_for(teacher, ws)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/photos")

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#go-to-photos")
  end

  test "the SG finds the Photos link on the register tab", %{sg: sg, ws: ws, cg: cg} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/classes/#{cg.id}/register")
    assert has_element?(view, ~s(#go-to-photos[href="/school/classes/#{cg.id}/photos"]))
  end
end
