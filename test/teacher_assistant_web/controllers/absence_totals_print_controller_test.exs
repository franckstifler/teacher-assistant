defmodule TeacherAssistantWeb.AbsenceTotalsPrintControllerTest do
  @moduledoc "« Bilan des absences » on paper: what the page shows, under the official header."
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.Academics.TypedAbsence
  alias TeacherAssistant.{Enrollment, Modules, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob Eto", sex: :m})
    [%{enrollment: awa} | _] = Enrollment.list_roster(scope, cg)
    [s1 | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.set_absence_hours_source(scope, cg, :typed_per_sequence)

    {:ok, _} =
      TypedAbsence
      |> Ash.Changeset.for_create(
        :set_for_sequence,
        %{enrollment_id: awa.id, sequence_id: s1.id, hours: Decimal.new(25)},
        scope: scope
      )
      |> Ash.create()

    %{cg: cg, s1: s1}
  end

  test "prints one class with its figures and the threshold", %{conn: conn, cg: cg, s1: s1} do
    body =
      conn
      |> get(~p"/school/absence-totals/print?#{[class: cg.id, period: "seq:#{s1.id}"]}")
      |> html_response(200)

    assert body =~ "Bilan des absences"
    assert body =~ cg.label
    assert body =~ "Awa Ngo"
    assert body =~ "Bob Eto"
    assert body =~ "Seuil : 20 h"
  end

  test "all classes prints only students over the threshold", %{conn: conn, s1: s1} do
    body =
      conn
      |> get(~p"/school/absence-totals/print?#{[period: "seq:#{s1.id}", seuil: "0,5"]}")
      |> html_response(200)

    assert body =~ "Awa Ngo"
    refute body =~ "Bob Eto"
  end

  test "a teacher is redirected", %{scope: scope, workspace: ws} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]}).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> log_in_user(teacher)
      |> Plug.Conn.put_session(:workspace_id, ws.id)
      |> get(~p"/school/absence-totals/print")

    assert redirected_to(conn) == ~p"/school"
  end

  test "the print belongs to the Discipline module" do
    assert Modules.module_for_controller(TeacherAssistantWeb.AbsenceTotalsPrintController, :show) ==
             :discipline
  end
end
