defmodule TeacherAssistantWeb.StatisticsPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head, scope: scope, year: year} do
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, maths} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    {:ok, a} =
      Assessment.create_assessment(scope, maths, seq, %{label: "D1", max_score: Decimal.new(20)})

    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: awa.id, score: Decimal.new("15.5")},
        %{student_id: bob.id, score: Decimal.new(7)}
      ])

    %{teacher: teacher} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

    %{seq: seq, cg: cg, teacher: teacher}
  end

  defp conn_for(%{workspace: ws}, user) do
    Phoenix.ConnTest.build_conn()
    |> log_in_user(user)
    |> Plug.Conn.put_session(:workspace_id, ws.id)
  end

  test "prints every course row with the period's figures", %{conn: conn, seq: seq} do
    html = conn |> get(~p"/school/statistics/me/print?period=seq:#{seq.id}") |> html_response(200)
    assert html =~ "Maths · 6e A"
    assert html =~ "11,25"
    assert html =~ "Séquence #{seq.number}"
    assert html =~ "Statistiques"
  end

  test "an admin prints a teacher's page by id; a teacher cannot print another's", ctx do
    html =
      ctx.conn
      |> get(~p"/school/statistics/me/print?teacher=#{ctx.teacher.id}")
      |> html_response(200)

    assert html =~ "SVT · 6e A"
    refute html =~ "Maths · 6e A"

    conn =
      conn_for(ctx, ctx.teacher) |> get(~p"/school/statistics/me/print?teacher=#{ctx.actor.id}")

    assert redirected_to(conn) == ~p"/school"
  end

  test "without a period, the current séquence is printed", %{conn: conn, seq: seq} do
    html = conn |> get(~p"/school/statistics/me/print") |> html_response(200)
    assert html =~ "Séquence #{seq.number}"
    assert html =~ "Maths · 6e A"
  end
end
