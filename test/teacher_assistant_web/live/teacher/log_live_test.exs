defmodule TeacherAssistantWeb.Teacher.LogLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  @moduletag :teacher_personal
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Curriculum.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, plan: plan, entry: entry}
  end

  test "logging a lesson records it", %{conn: conn, plan: plan, entry: entry} do
    {:ok, view, _html} = live(conn, "/teacher/log")

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

    assert length(Curriculum.list_logs_for_plan!(plan.id)) == 1
  end

  test "hours field shows its default value", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/teacher/log")
    assert view |> element("#log-form input[name='log[hours]']") |> render() =~ ~s(value="1")
  end

  test "saving stays on the page and shows the entry in the recent list", %{
    conn: conn,
    entry: entry
  } do
    {:ok, view, _html} = live(conn, "/teacher/log")

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
    {:ok, view, _html} = live(conn, "/teacher/log")

    html =
      view
      |> form("#log-form", log: %{hours: "abc"})
      |> render_change()

    assert html =~ "Saisissez les heures comme 1 ou 1,5"
  end

  describe "combined course" do
    setup %{conn: conn, actor: head} do
      {:ok, school} = Organization.create_school(head, %{name: "Lycée Log"})

      {:ok, year} =
        Organization.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg_a} = Enrollment.create_class_group(school, year, %{label: "1ère A", level: "1ère"})
      {:ok, cg_b} = Enrollment.create_class_group(school, year, %{label: "1ère B", level: "1ère"})

      {:ok, tc_a} = Curriculum.assign_teacher(cg_a, head, %{subject: "Mathématiques"})
      {:ok, tc_b} = Curriculum.assign_teacher(cg_b, head, %{subject: "Mathématiques"})

      # Pre-existing solo plans/lessons on each member class, created before
      # combining — these must NOT surface on the log once tc_a/tc_b share a
      # course plan.
      {:ok, stale_plan_a} = Curriculum.create_progression_plan(tc_a, %{title: "A (stale)"})
      {:ok, m_a} = Curriculum.create_module(stale_plan_a, %{title: "M"})

      {:ok, _stale_entry_a} =
        Curriculum.add_progression_entry(m_a, %{
          lesson_title: "Stale lesson A",
          planned_hours: Decimal.new("1"),
          entry_type: :lesson
        })

      {:ok, stale_plan_b} = Curriculum.create_progression_plan(tc_b, %{title: "B (stale)"})
      {:ok, m_b} = Curriculum.create_module(stale_plan_b, %{title: "M"})

      {:ok, _stale_entry_b} =
        Curriculum.add_progression_entry(m_b, %{
          lesson_title: "Stale lesson B",
          planned_hours: Decimal.new("1"),
          entry_type: :lesson
        })

      {:ok, course} = Curriculum.combine_course([tc_a, tc_b])

      [course_plan] =
        Curriculum.list_progression_plans!(school.id)
        |> Enum.filter(&(&1.combined_course_id == course.id))

      {:ok, course_module} = Curriculum.create_module(course_plan, %{title: "M"})

      {:ok, course_entry} =
        Curriculum.add_progression_entry(course_module, %{
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
      {:ok, view, _html} = live(conn, "/teacher/log")

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
