defmodule TeacherAssistantWeb.CardVerifyControllerTest do
  @moduledoc "Spec bulletin v2 §7: the ID card's QR opens a public check, no login."
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistantWeb.CardVerification

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture(%{name: "Lycée Carte"})
    :ok = TeacherFixtures.verify_school!(scope)
    TeacherFixtures.complete_school_setup!(scope)
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "Come 1", level: "1ère"})

    {:ok, st} =
      Enrollment.add_student(scope, cg, %{
        full_name: "Nlend Julienne",
        sex: :f,
        birth_date: ~D[2009-05-19]
      })

    {:ok, _} =
      Enrollment.add_guardian(scope, st, %{
        full_name: "Mme Nlend",
        phone: "677123456",
        relationship: :mere
      })

    [%{enrollment: enr}] = Enrollment.list_roster(scope, cg)
    %{scope: scope, cg: cg, enr: enr, year: year}
  end

  test "valid token shows school, name, class, year and current status", %{enr: enr, year: year} do
    token = CardVerification.token(enr.workspace_id, enr.id)
    html = build_conn() |> get(~p"/verify/card/#{token}") |> html_response(200)

    assert html =~ "Carte scolaire valide"
    assert html =~ "Lycée Carte"
    assert html =~ "Nlend Julienne"
    assert html =~ "Come 1"
    assert html =~ year.name
    assert html =~ "inscrit(e) cette année"
  end

  test "tampered token shows the invalid page", %{enr: enr} do
    token = CardVerification.token(enr.workspace_id, enr.id)
    tampered = String.slice(token, 0..-3//1) <> "AA"
    html = build_conn() |> get(~p"/verify/card/#{tampered}") |> html_response(200)
    assert html =~ "Code invalide"
    refute html =~ "Nlend Julienne"
  end

  test "page never shows birth date, photo or phone", %{enr: enr} do
    token = CardVerification.token(enr.workspace_id, enr.id)
    html = build_conn() |> get(~p"/verify/card/#{token}") |> html_response(200)
    refute html =~ "19/05/2009"
    refute html =~ "student_photo"
    refute html =~ "677123456"
  end

  test "card print embeds a QR per card", %{conn: conn, scope: scope, cg: cg} do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Ateba Ben", sex: :m})
    head = Ash.get!(TeacherAssistant.Accounts.User, scope.current_user.id, authorize?: false)

    html =
      conn
      |> log_in_user(head)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)
      |> get(~p"/school/classes/#{cg.id}/cards/print")
      |> html_response(200)

    assert length(Regex.scan(~r/class="card"/, html)) == 2
    assert length(Regex.scan(~r/<svg/, html)) == 2
  end
end
