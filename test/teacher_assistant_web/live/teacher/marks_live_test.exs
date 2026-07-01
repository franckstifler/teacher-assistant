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
    %{ws: ws, ctx: ctx, seq: seq, a: a, s1: s1}
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
end
