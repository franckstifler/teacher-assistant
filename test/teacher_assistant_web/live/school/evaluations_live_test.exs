defmodule TeacherAssistantWeb.School.EvaluationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée E"})

    scope = school_scope(user, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
    year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope, year: year, user: user}
  end

  test "settings links to the page, which shows the official defaults", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#evaluations-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#rule-annual_average_rule-mean_of_sequences[checked]")
    refute has_element?(view, "#rule-annual_average_rule-mean_of_trimesters[checked]")
    assert render(view) =~ "règle officielle"
    assert has_element?(view, "header a[href='/school/settings']", "Paramètres")
    assert has_element?(view, "h1", "Évaluations et moyennes")
  end

  test "choosing quarter rounding changes a class bulletin", ctx do
    %{conn: conn, scope: scope, year: year, user: user} = ctx
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, user, %{subject: "Maths", coefficient: Decimal.new(1)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st, enrollment: enr}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new("13.2")}])

    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> element("#rule-average_rounding-quarter") |> render_click()
    assert render(view) =~ "Réglage enregistré."
    assert has_element?(view, "#rule-average_rounding-quarter[checked]")

    # The on-screen bulletin embeds the print document, which carries the figures.
    html =
      conn
      |> get(~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}")
      |> html_response(200)

    assert html =~ "13,25"
    refute html =~ "13,20"
  end

  test "the tied-ranks toggle saves", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> element("#toggle-shared-ranks") |> render_click()
    refute Assessment.grading_rules(scope).shared_ranks?
  end

  test "a crafted unknown value is refused", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    render_hook(view, "set_rule", %{"field" => "average_rounding", "value" => "thousandth"})
    assert render(view) =~ "Réglage non enregistré."
    assert Assessment.grading_rules(scope).rounding == :hundredth
  end

  test "admin manages assessment types", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    refute has_element?(view, "#new-type-form")
    view |> element("#new-type-button") |> render_click()

    view
    |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0,5"}})
    |> render_submit()

    refute has_element?(view, "#type-drawer")
    oral = Enum.find(Assessment.list_assessment_types(scope), &(&1.name == "Oral"))
    assert Decimal.equal?(oral.default_weight, Decimal.new("0.5"))
    assert has_element?(view, "#type-weight-#{oral.id}[value='0,5']")

    view
    |> form("#types-form", %{
      "types" => %{oral.id => %{"name" => "Oral", "default_weight" => "2"}}
    })
    |> render_submit()

    assert Decimal.equal?(
             Enum.find(Assessment.list_assessment_types(scope), &(&1.id == oral.id)).default_weight,
             2
           )

    view |> element("#delete-type-#{oral.id}") |> render_click()
    refute Enum.any?(Assessment.list_assessment_types(scope), &(&1.id == oral.id))
  end

  test "every type saves through one form and one save", %{conn: conn, scope: scope} do
    [a, b | _] = Assessment.list_assessment_types(scope)
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#types-form[phx-hook=DirtyForm] .ta-savebar")
    assert has_element?(view, "#types-form button[type=submit]")
    refute has_element?(view, "#type-#{a.id} button[type=submit]")

    html =
      view
      |> form("#types-form", %{
        "types" => %{
          a.id => %{"name" => "Interro écrite", "default_weight" => "0,5"},
          b.id => %{"name" => b.name, "default_weight" => "3"}
        }
      })
      |> render_submit()

    assert html =~ "Types enregistrés."
    types = Map.new(Assessment.list_assessment_types(scope), &{&1.id, &1})
    assert types[a.id].name == "Interro écrite"
    assert Decimal.equal?(types[a.id].default_weight, Decimal.new("0.5"))
    assert Decimal.equal?(types[b.id].default_weight, 3)
  end

  test "an invalid row saves nothing and flags its fields", %{conn: conn, scope: scope} do
    [a, b | _] = Assessment.list_assessment_types(scope)
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")

    view
    |> form("#types-form", %{
      "types" => %{
        a.id => %{"name" => a.name, "default_weight" => "5"},
        b.id => %{"name" => "", "default_weight" => "0"}
      }
    })
    |> render_submit()

    assert has_element?(view, "#types-error")
    assert has_element?(view, "#type-name-#{b.id}.input-error")
    refute has_element?(view, "#type-name-#{a.id}.input-error")
    unchanged = Enum.find(Assessment.list_assessment_types(scope), &(&1.id == a.id))
    assert Decimal.equal?(unchanged.default_weight, a.default_weight)
  end

  test "a duplicate name rolls every row back", %{conn: conn, scope: scope} do
    [a, b | _] = Assessment.list_assessment_types(scope)
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")

    view
    |> form("#types-form", %{
      "types" => %{
        a.id => %{"name" => a.name, "default_weight" => "7"},
        b.id => %{"name" => a.name, "default_weight" => "1"}
      }
    })
    |> render_submit()

    assert has_element?(view, "#types-error", "même nom")
    unchanged = Enum.find(Assessment.list_assessment_types(scope), &(&1.id == a.id))
    assert Decimal.equal?(unchanged.default_weight, a.default_weight)
  end

  test "a zero weight is refused", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> element("#new-type-button") |> render_click()

    view
    |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0"}})
    |> render_submit()

    assert has_element?(view, "#type-drawer #new-type-error", "Type non enregistré.")
  end

  test "maximum mark and absence rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#rule-absence_rule-zero[checked]")

    view
    |> form("#entry-form", %{"entry" => %{"default_max_score" => "10"}})
    |> render_submit()

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert Decimal.equal?(profile.default_max_score, 10)

    view |> element("#rule-absence_rule-makeup") |> render_click()
    assert Assessment.grading_rules(scope).absence == :makeup
  end

  test "the admin sets the grade-entry grace days", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#entry-form[phx-hook=DirtyForm] .ta-savebar")

    html =
      view |> form("#entry-form", %{"entry" => %{"entry_grace_days" => "7"}}) |> render_submit()

    assert html =~ "Réglage enregistré."
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.entry_grace_days == 7

    html =
      view
      |> form("#entry-form", %{
        "entry" => %{"default_max_score" => "15", "entry_grace_days" => "40"}
      })
      |> render_submit()

    assert html =~ "Réglage non enregistré."
    assert has_element?(view, "#entry-grace-days-error")
    refute has_element?(view, "#default-max-error")
    # one update: the valid maximum is not saved alone
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.entry_grace_days == 7
    refute Decimal.equal?(profile.default_max_score, 15)

    view
    |> form("#entry-form", %{
      "entry" => %{"default_max_score" => "abc", "entry_grace_days" => "7"}
    })
    |> render_submit()

    assert has_element?(view, "#default-max-error")
    refute has_element?(view, "#entry-grace-days-error")
  end
end
