defmodule TeacherAssistantWeb.Teacher.MarksSummaryLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})

    :ok =
      Academics.upsert_marks(a, [
        %{student_id: s1.id, score: Decimal.new("14")},
        %{student_id: s2.id, score: Decimal.new("8")}
      ])

    %{ws: ws, ctx: ctx, seq: seq, cg: cg, s1: s1, s2: s2}
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
    s2: s2
  } do
    {:ok, ungraded} = Academics.add_student(cg, %{full_name: "Chantal", sex: :f})

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
    cg: cg
  } do
    {:ok, _ungraded} = Academics.add_student(cg, %{full_name: "Chantal", sex: :f})

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

  test "séquence switcher patches to the chosen séquence", %{conn: conn, ctx: ctx, ws: ws} do
    year = Academics.current_academic_year(ws)
    seq2 = Academics.list_sequences(year) |> Enum.at(1)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary")

    view
    |> element("#summary-seq-select")
    |> render_change(%{"seq" => seq2.id})

    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq2.id}")
    # séquence 2 has no assessments -> guided empty state, not stats
    refute has_element?(view, "#summary-class-average")
    assert render(view) =~ "No marks in this séquence yet"
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

  test "context without class group redirects to roster", %{conn: conn, ws: ws} do
    {:ok, year} = {:ok, Academics.current_academic_year(ws)}

    {:ok, ctx_no_roster} =
      Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/teacher/contexts/#{ctx_no_roster.id}/marks/summary")

    assert to =~ "/roster"
  end

  test "unknown teaching context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks/summary")
  end
end
