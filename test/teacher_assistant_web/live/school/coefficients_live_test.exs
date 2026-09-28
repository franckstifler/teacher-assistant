defmodule TeacherAssistantWeb.School.CoefficientsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée G"})

    scope = school_scope(user, school)
    year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "2nde Z", level: "2nde", serie: "C"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope, cg: cg, maths: maths, user: user}
  end

  defp tok(level, serie \\ nil), do: Curriculum.cell_token({:francophone, level, serie})

  test "settings links to the grid, which lists subjects by group", %{conn: conn, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#coefficients-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    assert has_element?(view, "#grid-row-#{m.id}", "Mathématiques")
    assert has_element?(view, "input[name='grid[cells][#{m.id}][#{tok("2nde")}]'][value='4']")
  end

  test "admin saves a coefficient and a group", %{conn: conn, scope: scope, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")

    view
    |> form("#coefficient-grid-form", %{
      "grid" => %{"cells" => %{m.id => %{tok("2nde") => "5"}}, "groups" => %{m.id => "g1_lettres"}}
    })
    |> render_submit()

    assert render(view) =~ "Coefficients enregistrés."
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 5)
  end

  test "clearing a cell a class uses is refused on that cell", ctx do
    {:ok, _} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.user, %{subject: ctx.maths})
    {:ok, view, _} = live(ctx.conn, ~p"/school/settings/coefficients")

    view
    |> form("#coefficient-grid-form", %{"grid" => %{"cells" => %{ctx.maths.id => %{tok("2nde") => ""}}}})
    |> render_submit()

    assert has_element?(view, "#grid-row-#{ctx.maths.id}", "Utilisée par : 2nde Z")
  end

  test "the série view edits série cells over the blank-série value", %{conn: conn, scope: scope, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    view |> element("#grid-view-francophone-C") |> render_click()
    assert has_element?(view, "input[name='grid[cells][#{m.id}][#{tok("2nde", "C")}]'][placeholder='4']")

    view
    |> form("#coefficient-grid-form", %{"grid" => %{"cells" => %{m.id => %{tok("2nde", "C") => "6"}}}})
    |> render_submit()

    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", "C"}].coefficient, 6)
  end

  test "switching overrides off is refused while a class has one", ctx do
    {:ok, tc} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.user, %{subject: ctx.maths})
    {:ok, _} = Curriculum.set_assignment_coefficient(ctx.scope, tc, "3")
    {:ok, view, _} = live(ctx.conn, ~p"/school/settings/coefficients")
    view |> element("#toggle-class-coefficients") |> render_click()
    assert render(view) =~ "2nde Z"
    assert {:ok, %{class_coefficients_allowed?: true}} = Accounts.fetch_school_profile(ctx.scope)
  end

  test "group subtotals toggle", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    view |> element("#toggle-group-subtotals") |> render_click()
    assert {:ok, %{bulletin_group_subtotals?: true}} = Accounts.fetch_school_profile(scope)
  end
end
