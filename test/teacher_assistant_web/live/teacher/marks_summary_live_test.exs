defmodule TeacherAssistantWeb.Teacher.MarksSummaryLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  setup %{workspace: ws, year: year, actor: head, scope: scope} do
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    seq = Organization.list_sequences(scope, year) |> List.first()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    {:ok, cg} = Enrollment.fetch_owned_class_group(scope, ctx.class_group_id)
    {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})

    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: s1.id, score: Decimal.new("14")},
        %{student_id: s2.id, score: Decimal.new("8")}
      ])

    %{ws: ws, ctx: ctx, seq: seq, cg: cg, s1: s1, s2: s2, scope: scope}
  end

  test "shows class average and pass rate", %{conn: conn, ctx: ctx, seq: seq, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert has_element?(view, "#teacher-marks-summary")
    # class average (14 + 8) / 2 = 11
    assert has_element?(view, "#summary-class-average", "11")
    # pass rate: 1 of 2 students >= 10 => 50%
    assert has_element?(view, "#summary-pass-rate", "50")
    assert has_element?(view, "#summary-row-#{s1.id}", "Awa")
    assert has_element?(view, "#summary-row-#{s1.id}", "14")
  end

  test "ungraded student is not badged as failing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg,
    s2: s2,
    scope: scope
  } do
    {:ok, ungraded} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    # ungraded student shows "—" and no mention badge at all
    ungraded_row = render(element(view, "#summary-row-#{ungraded.id}"))
    assert ungraded_row =~ "—"
    refute ungraded_row =~ "Insuffisant"

    # graded failing student (score 8 < 10) is still badged "Insuffisant"
    assert render(element(view, "#summary-row-#{s2.id}")) =~ "Insuffisant"
  end

  test "shows mention distribution, sex bars and missing-marks line", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg,
    scope: scope
  } do
    {:ok, _ungraded} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    # Awa 14 => Bien; Beba 8 => Insuffisant
    assert render(element(view, "#summary-mentions")) =~ "Bien"
    assert render(element(view, "#summary-mentions")) =~ "Insuffisant"
    assert has_element?(view, "#summary-sex-bars", "Filles")
    assert has_element?(view, "#summary-sex-bars", "Garçons")
    # 1 of 3 students has no marks
    assert has_element?(view, "#summary-missing", "1")
  end

  test "séquence switcher patches to the chosen séquence", %{conn: conn, ctx: ctx, scope: scope} do
    year = Organization.current_academic_year(scope)
    seq2 = Organization.list_sequences(scope, year) |> Enum.at(1)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary")

    view
    |> element("#summary-seq-select")
    |> render_change(%{"seq" => seq2.id})

    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq2.id}")
    # séquence 2 has no assessments -> guided empty state, not stats
    refute has_element?(view, "#summary-class-average")
    assert render(view) =~ "Pas encore de notes dans cette séquence"
  end

  test "renders a table with rank and mention columns", %{conn: conn, ctx: ctx, seq: seq, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert has_element?(view, "#summary-table")
    row = render(element(view, "#summary-row-#{s1.id}"))
    assert row =~ "Awa"
    assert row =~ "14"
    assert row =~ "Bien"
  end

  test "unknown teaching context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks/summary")
  end
end
