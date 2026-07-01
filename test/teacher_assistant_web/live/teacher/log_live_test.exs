defmodule TeacherAssistantWeb.Teacher.LogLiveTest do
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
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, plan: plan, entry: entry}
  end

  test "logging a lesson records it", %{conn: conn, plan: plan, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    view
    |> form("#log-form",
      log: %{
        progression_entry_id: entry.id,
        date: "2025-09-15",
        content_taught: "Intro",
        hours: "2",
        status: "done"
      }
    )
    |> render_submit()

    assert length(Academics.list_logs_for_plan(plan)) == 1
  end

  test "hours field shows its default value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")
    assert view |> element("#log-form input[name='log[hours]']") |> render() =~ ~s(value="1")
  end

  test "saving stays on the page and shows the entry in the recent list", %{
    conn: conn,
    entry: entry
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    view
    |> form("#log-form",
      log: %{
        progression_entry_id: entry.id,
        date: "2026-07-01",
        hours: "2",
        content_taught: "Fractions",
        status: "done"
      }
    )
    |> render_submit()

    # no navigation; ledger shows the new entry
    assert has_element?(view, "#log-recent", "Fractions")
  end

  test "invalid hours shows an inline error on change", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    html =
      view
      |> form("#log-form", log: %{hours: "abc"})
      |> render_change()

    assert html =~ "Enter hours like 1 or 1.5"
  end
end
