defmodule TeacherAssistantWeb.Teacher.MarksLiveTest do
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
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    %{ws: ws, ctx: ctx, seq: seq, a: a, s1: s1, cg: cg}
  end

  test "enters a mark for a student", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    view
    |> form("#marks-form", %{"scores" => %{s1.id => "15"}})
    |> render_submit()

    assert [m] = Academics.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("15"))
  end

  test "context without class group redirects to roster", %{conn: conn, ws: ws} do
    {:ok, year} = {:ok, Academics.current_academic_year(ws)}

    {:ok, ctx2} =
      Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/teacher/contexts/#{ctx2.id}/marks")

    assert to =~ "/roster"
  end

  test "unknown teaching context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks")
  end

  test "each score input has the student name as its accessible label", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#mark-input-#{s1.id}[aria-label='#{s1.full_name}']")
  end

  test "shows entry progress and live average preview", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    cg: cg
  } do
    {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-progress")

    html =
      view
      |> element("#marks-form")
      |> render_change(%{"scores" => %{s1.id => "14", s2.id => "10"}})

    assert html =~ "2"
    # average preview: (14 + 10) / 2 = 12
    assert view |> element("#marks-average-preview") |> render() =~ "12"
  end

  test "toolbar wraps séquence and assessment controls", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-toolbar #seq-select")
    assert has_element?(view, "#marks-toolbar #assessment-select")
  end

  test "md sheet shows sibling assessment scores read-only", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1
  } do
    {:ok, other} = Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})

    :ok =
      Academics.upsert_marks(other, [
        %{student_id: s1.id, score: Decimal.new("17")}
      ])

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-sheet-header", "Devoir 2")
    assert render(element(view, "#mark-row-#{s1.id}")) =~ "17"
  end
end
