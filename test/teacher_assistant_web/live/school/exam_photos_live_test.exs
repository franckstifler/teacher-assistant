defmodule TeacherAssistantWeb.School.ExamPhotosLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, StudentPhotos}
  alias TeacherAssistant.TeacherFixtures

  @jpeg "test/support/fixtures/files/1x1.jpg"

  setup do
    %{scope: scope, year: year, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}

    {:ok, f3} =
      Enrollment.create_class_group(scope, year, %{label: "1ère F3", level: "1ère", serie: "F3"})

    {:ok, tle} =
      Enrollment.create_class_group(scope, year, %{
        label: "Tle CG",
        level: "Terminale",
        serie: "CG"
      })

    {:ok, seconde} =
      Enrollment.create_class_group(scope, year, %{label: "2nde F3", level: "2nde", serie: "F3"})

    {:ok, awa} = Enrollment.add_student(scope, f3, %{full_name: "Awa Ngono", sex: :f})
    {:ok, _ben} = Enrollment.add_student(scope, f3, %{full_name: "Ben Ateba", sex: :m})
    {:ok, zoe} = Enrollment.add_student(scope, tle, %{full_name: "Zoé", sex: :f})
    {:ok, _} = StudentPhotos.store(scope, awa, @jpeg)
    {:ok, _} = StudentPhotos.store(scope, zoe, @jpeg)

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})

    %{scope: scope, ws: ws, f3: f3, cg_tle: tle, seconde: seconde, awa: awa, zoe: zoe, sg: sg}
  end

  defp conn_for(scope, ws),
    do:
      build_conn()
      |> log_in_user(scope.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

  test "lists exam classes only, with the suggested code", %{
    sg: sg,
    ws: ws,
    f3: f3,
    cg_tle: tle,
    seconde: seconde
  } do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    assert has_element?(view, "#exam-class-#{f3.id} input[name=exam_code][value=PBF3]")
    assert has_element?(view, "#exam-class-#{tle.id}")
    refute has_element?(view, "#exam-class-#{seconde.id}")
    assert view |> element("#exam-count-#{f3.id}") |> render() =~ "1 / 2"
  end

  test "a teacher is sent away", %{scope: head, ws: ws} do
    teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(teacher, ws), ~p"/school/exam-photos")
  end

  test "saving codes stores them on the class", %{sg: sg, ws: ws, f3: f3} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")

    view
    |> form("#exam-class-#{f3.id} form", %{
      class_id: f3.id,
      exam_code: "PBF3",
      exam_center_code: "CR 8127"
    })
    |> render_change()

    assert {:ok, %{exam_code: "PBF3", exam_center_code: "CR 8127"}} =
             Enrollment.fetch_owned_class_group(sg, f3.id)
  end

  test "the default CR code fills only empty classes", %{sg: sg, ws: ws, f3: f3, cg_tle: tle} do
    {:ok, _} = Enrollment.set_exam_codes(f3, %{exam_center_code: "CR 1"}, scope: sg)
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    view |> form("#exam-default-center", %{center: "CR 8127"}) |> render_submit()
    assert {:ok, %{exam_center_code: "CR 1"}} = Enrollment.fetch_owned_class_group(sg, f3.id)
    assert {:ok, %{exam_center_code: "CR 8127"}} = Enrollment.fetch_owned_class_group(sg, tle.id)
  end

  test "ticked students without a photo are counted and left out", %{sg: sg, ws: ws, f3: f3} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    assert view |> element("#exam-left-out") |> render() =~ "1"
    view |> element("#exam-zip-#{f3.id}") |> render_click()

    assert_push_event(view, "exam-photos:build", %{
      zip_name: "photos-examen-1ERE_F3.zip",
      items: [item]
    })

    assert item.file == "PBF3_AWA_NGONO.jpg"
    assert item.folder == "1ERE_F3"
    assert item.names == ["AWA NGONO"]
  end

  test "ticks carry across classes into the selection export", %{
    sg: sg,
    ws: ws,
    f3: f3,
    awa: awa
  } do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    view |> element("#exam-open-#{f3.id}") |> render_click()
    view |> element("#exam-none-#{f3.id}") |> render_click()
    view |> element("#exam-tick-#{awa.id}") |> render_click()
    assert view |> element("#exam-zip-selection") |> render() =~ "2"
    view |> element("#exam-zip-selection") |> render_click()
    assert_push_event(view, "exam-photos:build", %{items: items})
    assert items |> Enum.map(& &1.photo_url) |> length() == 2
  end

  test "a class without a suggestion exports with an empty code", %{
    sg: sg,
    ws: ws,
    cg_tle: tle
  } do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    view |> element("#exam-zip-#{tle.id}") |> render_click()

    assert_push_event(view, "exam-photos:build", %{
      items: [%{file: "SANS-CODE_ZOE.jpg", codes: ""}]
    })
  end

  test "a failed export tells the user how many photos were skipped", %{sg: sg, ws: ws} do
    {:ok, view, _} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    assert render_hook(view, "export_failed", %{"count" => 2}) =~ "2 photos n&#39;ont pas pu"
  end

  test "the SG's menu links to the page", %{sg: sg, ws: ws} do
    {:ok, _view, html} = live(conn_for(sg, ws), ~p"/school/exam-photos")
    assert html =~ ~s(href="/school/exam-photos")
  end
end
