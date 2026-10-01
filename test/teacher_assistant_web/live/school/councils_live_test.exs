defmodule TeacherAssistantWeb.School.CouncilsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Councils, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, actor: head} do
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Djoumessi Arnaud", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Tchinda Rodrigue", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    [term | _] = Organization.list_terms(scope, year)
    [seq1 | _] = term.sequences

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq1, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [dj, tch] = Enrollment.list_roster(scope, cg)

    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: dj.student.id, score: Decimal.new(15)},
        %{student_id: tch.student.id, score: Decimal.new(7)}
      ])

    %{scope: scope, cg: cg, term: term, dj: dj.student, tch: tch.student}
  end

  defp council_path(cg, term), do: ~p"/school/councils/#{cg.id}?term=#{term.id}"

  defp conn_for(scope, user) do
    build_conn()
    |> log_in_user(user)
    |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)
  end

  test "the list shows each class with its entry rate and status", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
    assert has_element?(view, "#council-row-#{ctx.cg.id}", "4e B")
    assert has_element?(view, "#council-row-#{ctx.cg.id}", "Saisie incomplète")
    assert has_element?(view, "#councils-ready", "0 /")

    view |> element("#council-row-#{ctx.cg.id} a") |> render_click()
    assert_redirect(view, council_path(ctx.cg, ctx.term))
  end

  test "the page saves the header and shows the proposals by rank", ctx do
    {:ok, view, _} = live(ctx.conn, council_path(ctx.cg, ctx.term))
    assert has_element?(view, "#council-stats")
    assert has_element?(view, "#decision-#{ctx.dj.id}", "Encouragements")
    assert has_element?(view, "#decision-#{ctx.tch.id}", "Avertissement travail")

    view
    |> form("#council-header-form", %{council: %{chair: "M. Fotso", attendees: "Censeur, PP"}})
    |> render_submit()

    assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).chair == "M. Fotso"
  end

  test "changing a row saves the student's decision", ctx do
    {:ok, view, _} = live(ctx.conn, council_path(ctx.cg, ctx.term))

    view
    |> form("#decision-#{ctx.tch.id}", %{
      decision: %{conduct_warning: "avertissement_conduite", appreciation: "Doit se ressaisir"}
    })
    |> render_change()

    assert has_element?(view, "#saved-#{ctx.tch.id}")

    assert [d] = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions
    assert d.student_id == ctx.tch.id
    assert d.conduct_warning == :avertissement_conduite
    assert d.appreciation == "Doit se ressaisir"
  end

  test "holding below complete entry asks for confirmation; reopen", ctx do
    {:ok, view, _} = live(ctx.conn, council_path(ctx.cg, ctx.term))
    view |> element("#hold-council") |> render_click()
    assert has_element?(view, "#hold-confirm", "Saisie incomplète")
    refute Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})

    view |> element("#confirm-hold") |> render_click()
    assert has_element?(view, "#council-status", "Tenu")
    assert Councils.held?(ctx.scope, ctx.cg, {:trimester, ctx.term})

    view |> element("#reopen-council") |> render_click()
    assert has_element?(view, "#council-status", "Ouvert")
  end

  test "a published term locks the council", ctx do
    {:ok, _} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    {:ok, view, _} = live(ctx.conn, council_path(ctx.cg, ctx.term))
    assert has_element?(view, "#council-locked")
    refute has_element?(view, "#hold-council")
    refute has_element?(view, "#reopen-council")

    render_change(view, "decision", %{
      "student_id" => ctx.tch.id,
      "decision" => %{"appreciation" => "X"}
    })

    assert render(view) =~ "Conseil verrouillé : bulletins publiés."
    assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions == []
  end

  test "only the admin axis opens council screens; the head has the menu item", ctx do
    other = TeacherFixtures.member_scope_fixture(ctx.scope)
    oconn = conn_for(ctx.scope, other.current_user)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(oconn, ~p"/school/councils")

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(oconn, council_path(ctx.cg, ctx.term))

    {:ok, view, _} = live(ctx.conn, ~p"/school/councils")
    assert has_element?(view, "a[href='/school/councils']")
  end
end
