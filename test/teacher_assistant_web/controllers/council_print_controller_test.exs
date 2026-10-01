defmodule TeacherAssistantWeb.CouncilPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Assessment, Councils, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e A", level: "3ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Ekani Paul", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(2)})

    [term | _] = Organization.list_terms(scope, year)

    {:ok, a} =
      Assessment.create_assessment(scope, tc, hd(term.sequences), %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new(9)}])
    %{scope: scope, year: year, cg: cg, term: term, st: st, tc: tc}
  end

  defp pv(conn, cg, term), do: get(conn, ~p"/school/councils/#{cg.id}/print?term=#{term.id}")

  test "the procès-verbal lists the council and its decisions", ctx do
    {:ok, _} =
      Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{"chair" => "M. Abena"})

    {:ok, _} =
      Councils.set_decision(ctx.scope, ctx.cg, {:trimester, ctx.term}, ctx.st.id, %{
        "conduct_warning" => "avertissement_conduite",
        "appreciation" => "Peut mieux faire"
      })

    html = ctx.conn |> pv(ctx.cg, ctx.term) |> html_response(200)
    assert html =~ "3e A"
    assert html =~ "PROJET"
    assert html =~ "M. Abena"
    assert html =~ "Ekani Paul"
    assert html =~ "Peut mieux faire"
    assert html =~ "Avertissement de conduite"

    {:ok, _} = Councils.hold(ctx.scope, ctx.cg, {:trimester, ctx.term})
    refute ctx.conn |> pv(ctx.cg, ctx.term) |> html_response(200) =~ "PROJET"
  end

  test "a class with no subjects still prints", ctx do
    {:ok, bare} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e Z", level: "6ème"})

    html = ctx.conn |> pv(bare, ctx.term) |> html_response(200)
    assert html =~ "6e Z"
    assert html =~ "—"
  end

  test "only the admin axis prints it", ctx do
    other = TeacherFixtures.member_scope_fixture(ctx.scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)
      |> pv(ctx.cg, ctx.term)

    assert redirected_to(conn) == "/school"
  end

  test "a published term's procès-verbal prints the frozen figures", ctx do
    {:ok, _} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    [a] = Assessment.list_assessments(ctx.scope, ctx.tc, hd(ctx.term.sequences))

    :ok =
      Assessment.upsert_marks(ctx.scope, a, [%{student_id: ctx.st.id, score: Decimal.new(16)}])

    html = ctx.conn |> pv(ctx.cg, ctx.term) |> html_response(200)
    assert html =~ "9.00"
    refute html =~ "16.00"
  end

  describe "annual council (I4)" do
    test "the annual procès-verbal lists passage decisions and their counts", ctx do
      url = ~p"/school/councils/#{ctx.cg.id}/print?period=annee"
      html = ctx.conn |> get(url) |> html_response(200)
      assert html =~ "Conseil de fin d"
      assert html =~ "Redouble"
      assert html =~ "Redouble : 1"

      {:ok, _} =
        Councils.set_decision(ctx.scope, ctx.cg, {:annual, ctx.year}, ctx.st.id, %{
          "passage_decision" => "exclu"
        })

      html = ctx.conn |> get(url) |> html_response(200)
      assert html =~ "Exclu : 1"
    end

    test "a trimester procès-verbal has no passage", ctx do
      html = ctx.conn |> pv(ctx.cg, ctx.term) |> html_response(200)
      refute html =~ "Redouble"
    end
  end
end
