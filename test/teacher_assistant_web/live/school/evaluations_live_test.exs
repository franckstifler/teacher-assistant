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
    assert has_element?(view, "#rule-annual_average_rule-mean_of_sequences.btn-primary")
    assert render(view) =~ "règle officielle"
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

    {:ok, _, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "13.25"
    refute html =~ "13.20"
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

    view
    |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0,5"}})
    |> render_submit()

    oral = Enum.find(Assessment.list_assessment_types(scope), &(&1.name == "Oral"))
    assert Decimal.equal?(oral.default_weight, Decimal.new("0.5"))

    view
    |> form("#type-#{oral.id}", %{"type" => %{"name" => "Oral", "default_weight" => "2"}})
    |> render_submit()

    assert Decimal.equal?(
             Enum.find(Assessment.list_assessment_types(scope), &(&1.id == oral.id)).default_weight,
             2
           )

    view |> element("#delete-type-#{oral.id}") |> render_click()
    refute Enum.any?(Assessment.list_assessment_types(scope), &(&1.id == oral.id))
  end

  test "a zero weight is refused", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")

    view
    |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0"}})
    |> render_submit()

    assert render(view) =~ "Type non enregistré."
  end

  test "maximum mark and absence rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#rule-absence_rule-zero.btn-primary")
    view |> form("#default-max-form", %{"default_max_score" => "10"}) |> render_submit()
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert Decimal.equal?(profile.default_max_score, 10)

    view |> element("#rule-absence_rule-makeup") |> render_click()
    assert Assessment.grading_rules(scope).absence == :makeup
  end
end
