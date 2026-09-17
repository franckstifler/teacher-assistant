defmodule TeacherAssistantWeb.Teacher.LogLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Courses}
  alias TeacherAssistant.Accounts.Schools
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

    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Academics.add_progression_entry(m1, %{
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

    assert html =~ "Saisissez les heures comme 1 ou 1,5"
  end

  describe "combined course" do
    setup %{conn: conn, actor: head} do
      {:ok, school} = Schools.create_school(head, %{name: "Lycée Log"})

      {:ok, year} =
        Academics.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg_a} = Academics.create_class_group(school, year, %{label: "1ère A", level: "1ère"})
      {:ok, cg_b} = Academics.create_class_group(school, year, %{label: "1ère B", level: "1ère"})

      {:ok, tc_a} = Assignments.assign(cg_a, head, %{subject: "Mathématiques"})
      {:ok, tc_b} = Assignments.assign(cg_b, head, %{subject: "Mathématiques"})

      # Pre-existing solo plans/lessons on each member class, created before
      # combining — these must NOT surface on the log once tc_a/tc_b share a
      # course plan.
      {:ok, stale_plan_a} = Academics.create_progression_plan(tc_a, %{title: "A (stale)"})
      {:ok, m_a} = Academics.create_module(stale_plan_a, %{title: "M"})

      {:ok, _stale_entry_a} =
        Academics.add_progression_entry(m_a, %{
          lesson_title: "Stale lesson A",
          planned_hours: Decimal.new("1"),
          entry_type: :lesson
        })

      {:ok, stale_plan_b} = Academics.create_progression_plan(tc_b, %{title: "B (stale)"})
      {:ok, m_b} = Academics.create_module(stale_plan_b, %{title: "M"})

      {:ok, _stale_entry_b} =
        Academics.add_progression_entry(m_b, %{
          lesson_title: "Stale lesson B",
          planned_hours: Decimal.new("1"),
          entry_type: :lesson
        })

      {:ok, course} = Courses.combine([tc_a, tc_b])

      [course_plan] =
        Academics.list_progression_plans(school)
        |> Enum.filter(&(&1.combined_course_id == course.id))

      {:ok, course_module} = Academics.create_module(course_plan, %{title: "M"})

      {:ok, course_entry} =
        Academics.add_progression_entry(course_module, %{
          lesson_title: "Course lesson",
          planned_hours: Decimal.new("1"),
          entry_type: :lesson
        })

      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

      %{conn: conn, course: course, course_entry: course_entry}
    end

    test "teaching log does not double-list a combined course's stale member-plan lessons", %{
      conn: conn,
      course_entry: course_entry
    } do
      {:ok, view, _html} = live(conn, ~p"/teacher/log")

      html = render(view)

      assert html =~ "Course lesson"
      refute html =~ "Stale lesson A"
      refute html =~ "Stale lesson B"

      assert has_element?(
               view,
               "#log-form select[name='log[progression_entry_id]'] option[value='#{course_entry.id}']"
             )
    end
  end
end
