defmodule TeacherAssistantWeb.School.NewYearLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Councils, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, a6} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, a5} = Enrollment.create_class_group(scope, year, %{label: "5ème A", level: "5ème"})
    {:ok, awa} = Enrollment.add_student(scope, a6, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, a6, %{full_name: "Bob", sex: :m})

    for {s, d} <- [{awa, "admis"}, {bob, "redouble"}] do
      {:ok, _} =
        Councils.set_decision(scope, a6, {:annual, year}, s.id, %{"passage_decision" => d})
    end

    %{a6: a6, a5: a5}
  end

  test "a teacher is sent back to /school", %{scope: scope, workspace: school} do
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/settings/new-year")
  end

  test "settings links to the wizard for the open year", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, ~s|#new-year-link[href="/school/settings/new-year"]|)
  end

  test "four steps from checks to the new year", %{conn: conn, scope: scope} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")

    assert has_element?(view, "#step-checks")
    assert has_element?(view, "#check-councils", "6ème A")
    assert has_element?(view, "#check-before-end")

    view |> element("#to-step-2") |> render_click()
    # Default dates: the old ones + 1 year.
    assert view |> element("#new-year-form") |> render() =~ "2026-09-08"

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    assert has_element?(view, "#class-row-#{ctx.a6.id}")
    # Awa is admis into the copy of 5ème A, Bob repeats 6ème A.
    assert has_element?(view, "#class-size-#{ctx.a5.id}", "1 élève")
    assert has_element?(view, "#class-size-#{ctx.a6.id}", "1")

    view |> form("#classes-form", %{"targets" => %{ctx.a6.id => ""}}) |> render_change()
    assert has_element?(view, "#class-size-#{ctx.a5.id}", "0 élève")

    view |> form("#classes-form") |> render_submit()
    assert has_element?(view, "#summary-reenrolled", "1")
    assert has_element?(view, "#summary-repeaters", "1")
    assert has_element?(view, "#summary-not", "1")

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             view |> element("#start-year") |> render_click()

    assert Organization.current_academic_year(scope).name == "2026-2027"
  end

  test "blank or duplicate labels are refused at step 3", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")
    view |> element("#to-step-2") |> render_click()

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    view |> form("#classes-form", %{"labels" => %{ctx.a5.id => "6ème A"}}) |> render_submit()
    assert has_element?(view, "#classes-error")
    refute has_element?(view, "#step-summary")

    view |> form("#classes-form", %{"labels" => %{ctx.a5.id => "  "}}) |> render_submit()
    assert has_element?(view, "#classes-error")
  end

  test "an end before the start, or a name already used, stays on step 2", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")
    view |> element("#to-step-2") |> render_click()

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2026-01-01"}
    )
    |> render_submit()

    assert has_element?(view, "#year-error")

    view
    |> form("#new-year-form",
      year: %{name: "Année de référence", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    assert has_element?(view, "#year-error")
    refute has_element?(view, "#classes-form")
  end
end
