defmodule TeacherAssistantWeb.Teacher.FicheLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})
    %{plan: plan, ctx: ctx}
  end

  test "redirects to /teacher when accessing another user's plan (IDOR)", %{conn: conn} do
    other_user = TeacherFixtures.user_fixture()
    other_ws = Academics.ensure_personal_workspace!(other_user)

    {:ok, year} =
      Academics.create_academic_year(other_ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(other_ws, year, %{
        subject: "Physics",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 3
      })

    {:ok, other_plan} = Academics.create_progression_plan(ctx, %{title: "Other Plan"})

    assert {:error, {:live_redirect, %{to: "/teacher"}}} =
             live(conn, ~p"/teacher/plans/#{other_plan.id}")
  end

  test "add a module then a lesson into it", %{conn: conn, plan: plan} do
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view |> form("#add-module-form", %{module: %{title: "Algorithmique"}}) |> render_submit()
    assert render(view) =~ "Algorithmique"

    module = Academics.list_progression_modules(plan) |> Enum.find(&(&1.title == "Algorithmique"))

    view
    |> form("#add-entry-form-#{module.id}",
      entry: %{lesson_title: "Les boucles", planned_hours: "2", entry_type: "lesson"}
    )
    |> render_submit()

    assert render(view) =~ "Les boucles"
  end

  test "delete a module reassigns its lessons to the default bucket", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})

    {:ok, _} =
      Academics.add_progression_entry(m, %{lesson_title: "Orpheline", entry_type: :lesson})

    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view |> element("#module-delete-#{m.id}") |> render_click()

    assert render(view) =~ "Orpheline"
    refute Academics.list_progression_modules(plan) |> Enum.any?(&(&1.id == m.id))
  end

  test "shows a running planned-hours total with weeks estimate", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})

    {:ok, _e} =
      Academics.add_progression_entry(m, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("6"),
        entry_type: :lesson
      })

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    assert has_element?(view, "#fiche-hours-total")
    total = render(element(view, "#fiche-hours-total"))
    assert total =~ "6"
    # 6h at 4 h/week (setup ctx) => ≈ 2 weeks
    assert total =~ "2"
  end

  test "each entry links to its lesson plan and shows a prepared indicator", %{
    conn: conn,
    plan: plan
  } do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Academics.add_progression_entry(m, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    # prepare link present, not-yet-prepared (no indicator)
    assert has_element?(view, "#entry-prepare-#{entry.id}")
    refute has_element?(view, "#entry-prepared-#{entry.id}")

    # once a fiche exists, the indicator shows on reload
    {:ok, ctx} = TeacherAssistant.Academics.get_teaching_context(plan.teaching_context_id)
    {:ok, _lp} = TeacherAssistant.Academics.ensure_lesson_plan(entry, ctx)

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")
    assert has_element?(view, "#entry-prepared-#{entry.id}")
  end

  test "rename module inline updates the title", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "Ancien titre"})

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view
    |> form("#rename-module-form-#{m.id}", %{"module_id" => m.id, "title" => "Nouveau titre"})
    |> render_submit()

    assert render(view) =~ "Nouveau titre"
    refute render(view) =~ "Ancien titre"

    assert Academics.list_progression_modules(plan)
           |> Enum.find(&(&1.id == m.id))
           |> Map.fetch!(:title) == "Nouveau titre"
  end

  test "apply-layout event reorders modules and moves a lesson", %{conn: conn, plan: plan} do
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, a} = Academics.add_progression_entry(m1, %{lesson_title: "A", entry_type: :lesson})
    {:ok, c} = Academics.add_progression_entry(m2, %{lesson_title: "C", entry_type: :lesson})

    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    render_hook(view, "apply-layout", %{
      "layout" => [
        %{"module_id" => m2.id, "entry_ids" => [c.id, a.id]},
        %{"module_id" => m1.id, "entry_ids" => []}
      ]
    })

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M2", "M1"]
    assert Enum.map(hd(mods).entries, & &1.lesson_title) == ["C", "A"]
  end

  test "quota header renders planned-vs-annual and count read-outs", %{
    conn: conn,
    plan: plan,
    ctx: ctx,
    workspace: ws
  } do
    {:ok, _} =
      Academics.update_teaching_context(ctx.id, ws, %{
        annual_hours: Decimal.new("50"),
        target_lesson_count: 3
      })

    {:ok, m} = Academics.create_module(plan, %{title: "M1"})

    {:ok, _} =
      Academics.add_progression_entry(m, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")
    html = render(view)
    assert html =~ "50"
    assert html =~ "quota-header"
  end

  test "save-targets persists context targets", %{conn: conn, plan: plan} do
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view
    |> form("#targets-form", %{
      targets: %{annual_hours: "75", target_module_count: "4", target_lesson_count: "21"}
    })
    |> render_submit()

    ctx = Academics.get_teaching_context(plan.teaching_context_id) |> elem(1)
    assert Decimal.equal?(ctx.annual_hours, Decimal.new("75"))
    assert ctx.target_lesson_count == 21
  end

  test "save-module-credit persists a module credit", %{conn: conn, plan: plan, workspace: ws} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view
    |> form("#module-credit-form-#{m.id}", %{credit_hours: "11", module_id: m.id})
    |> render_submit()

    m = Academics.fetch_owned_module(m.id, ws) |> elem(1)
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
end
