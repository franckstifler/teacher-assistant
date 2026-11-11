defmodule TeacherAssistantWeb.EntryReportPrintControllerTest do
  @moduledoc "The censeur's printed mark-entry report: every teacher's rate, who is behind."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head, scope: scope, year: year} do
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, maths} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    {:ok, a} =
      Assessment.create_assessment(scope, maths, seq, %{label: "D1", max_score: Decimal.new(20)})

    # Maths: 1 of 2 marks entered (50 %); SVT: no assessment yet (0 %).
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: awa.id, score: Decimal.new(14)}])

    %{teacher: teacher} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

    %{seq: seq, cg: cg, teacher: teacher}
  end

  defp conn_for(%{workspace: ws}, user) do
    Phoenix.ConnTest.build_conn()
    |> log_in_user(user)
    |> Plug.Conn.put_session(:workspace_id, ws.id)
  end

  test "lists every teacher's rate and the courses still to fill",
       %{conn: conn, seq: seq} = ctx do
    html = conn |> get(~p"/school/sequences/print?seq=#{seq.id}") |> html_response(200)
    doc = LazyHTML.from_document(html)

    assert html =~ "Suivi de la saisie des notes"
    assert html =~ "Séquence #{seq.number}"

    rates = doc |> LazyHTML.query("#entry-report-teachers tbody tr") |> LazyHTML.text()
    assert rates =~ "50 %"
    assert rates =~ "0 / 1"
    assert html =~ "un cours sans devoir compte 0 %"
    assert rates =~ "0 %"

    late = doc |> LazyHTML.query("#entry-report-late") |> LazyHTML.text()
    assert late =~ "Maths"
    assert late =~ "SVT"
    assert late =~ "Aucun devoir"
    assert late =~ TeacherAssistant.Accounts.User.display_name(ctx.teacher)
    assert html =~ "Le Censeur"
  end

  test "without a séquence, the default one is printed", %{conn: conn, seq: seq} do
    html = conn |> get(~p"/school/sequences/print") |> html_response(200)
    assert html =~ "Séquence #{seq.number}"
  end

  test "a teacher cannot print it", ctx do
    conn = conn_for(ctx, ctx.teacher) |> get(~p"/school/sequences/print")
    assert redirected_to(conn) == ~p"/school"
  end

  test "the tracking page links to it for the chosen séquence", %{conn: conn, seq: seq} do
    {:ok, view, _} = live(conn, ~p"/school/sequences?seq=#{seq.id}")

    assert has_element?(
             view,
             ~s(#print-entry-report[href="/school/sequences/print?seq=#{seq.id}"])
           )
  end
end
