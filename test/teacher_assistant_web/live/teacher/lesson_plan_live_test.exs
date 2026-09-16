defmodule TeacherAssistantWeb.Teacher.LessonPlanLiveTest do
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

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Academics.add_progression_entry(m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson,
        competence_visee: "Résoudre un problème"
      })

    %{ws: ws, entry: entry}
  end

  test "renders the cartouche and prefilled header", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    assert has_element?(view, "#lesson-plan")
    # derived cartouche
    assert render(view) =~ "Maths"
    assert render(view) =~ "6e A" or render(view) =~ "6ème"
    # prefilled header field
    assert has_element?(
             view,
             "#fiche-header-form input[name='lesson_plan[titre]'][value='Les entiers']"
           )
  end

  test "autosaves a header field on blur", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    view
    |> element("#fiche-header-form")
    |> render_change(%{
      "_target" => ["lesson_plan", "situation_probleme"],
      "lesson_plan" => %{"situation_probleme" => "Au marché"}
    })

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    assert lp.situation_probleme == "Au marché"
    assert has_element?(view, "#fiche-saved-indicator")
  end

  test "autosave forms debounce on blur (no per-keystroke writes)", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")
    view |> element("#step-add") |> render_click()

    html = render(view)
    # header form and step forms carry phx-debounce="blur"; no stray phx-blur binding remains
    assert html =~ ~s(phx-debounce="blur")
    assert has_element?(view, "#fiche-header-form[phx-debounce='blur']")
    refute html =~ ~s(phx-blur="save_header")
    refute html =~ ~s(phx-blur="save_step")
  end

  test "unknown entry redirects to /teacher", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher"}}} =
             live(conn, ~p"/teacher/entries/#{Ecto.UUID.generate()}/fiche")
  end

  test "adds, edits, reorders and deletes steps", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    # empty state first
    assert render(view) =~ "Aucune étape"

    view |> element("#step-add") |> render_click()
    view |> element("#step-add") |> render_click()

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    [s1, s2] = Academics.list_lesson_steps(lp)

    # edit step 1's étape (autosave fires on the change/blur event)
    view
    |> element("#step-row-#{s1.id} form")
    |> render_change(%{"_target" => ["step", "etape"], "step" => %{"etape" => "Découverte"}})

    assert Academics.list_lesson_steps(lp) |> List.first() |> Map.get(:etape) == "Découverte"

    # move step 1 down
    view |> element("#step-down-#{s1.id}") |> render_click()
    assert Academics.list_lesson_steps(lp) |> Enum.map(& &1.id) == [s2.id, s1.id]

    # delete step 2 (now first)
    view |> element("#step-delete-#{s2.id}") |> render_click()
    assert Academics.list_lesson_steps(lp) |> Enum.map(& &1.id) == [s1.id]
  end

  test "shows the running-duration check", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")
    view |> element("#step-add") |> render_click()

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    [s1] = Academics.list_lesson_steps(lp)

    view
    |> element("#step-row-#{s1.id} form")
    |> render_change(%{
      "_target" => ["step", "duration_minutes"],
      "step" => %{"duration_minutes" => "20"}
    })

    assert render(element(view, "#fiche-duration-check")) =~ "20"
  end

  test "duration check flags when steps exceed the planned lesson duration", %{
    conn: conn,
    entry: entry
  } do
    # entry planned_hours = 1 => lesson plan duration_minutes = 60
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")
    view |> element("#step-add") |> render_click()

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    [s1] = Academics.list_lesson_steps(lp)

    # under budget: no warning tone
    refute render(element(view, "#fiche-duration-check")) =~ "text-warning"

    # push the step over the 60-min budget
    view
    |> element("#step-row-#{s1.id} form")
    |> render_change(%{
      "_target" => ["step", "duration_minutes"],
      "step" => %{"duration_minutes" => "90"}
    })

    assert render(element(view, "#fiche-duration-check")) =~ "text-warning"
  end
end
