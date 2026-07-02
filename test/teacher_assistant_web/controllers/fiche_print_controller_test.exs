defmodule TeacherAssistantWeb.FichePrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
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

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    {:ok, _} = Academics.add_lesson_step(lp, %{etape: "Découverte", contenus: "les nombres"})
    %{entry: entry}
  end

  test "renders the printable fiche with header and steps", %{conn: conn, entry: entry} do
    conn = get(conn, ~p"/teacher/entries/#{entry.id}/fiche/print")
    html = html_response(conn, 200)

    assert html =~ "Les entiers"
    assert html =~ "Découverte"
    assert html =~ "les nombres"
    # cartouche carries année scolaire + enseignant
    assert html =~ "2025-2026"
    assert html =~ "@example.com"
    # print layout: no app nav
    refute html =~ ~s(id="main-nav")
  end

  test "a foreign entry redirects to /teacher", %{conn: conn} do
    conn = get(conn, ~p"/teacher/entries/#{Ecto.UUID.generate()}/fiche/print")
    assert redirected_to(conn) == "/teacher"
  end
end
