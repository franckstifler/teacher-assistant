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

    %{ctx: ctx, seq: seq, s1: s1, s2: s2}
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

  test "unknown teaching context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks/summary")
  end
end
