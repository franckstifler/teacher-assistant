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
    assert has_element?(view, "#council-row-#{ctx.cg.id}", "Notes 50 %")

    view |> element("#class-link-#{ctx.cg.id}") |> render_click()
    assert_redirect(view, council_path(ctx.cg, ctx.term))
  end

  test "classes are grouped by level, each with its state, and filtered by status", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
    assert has_element?(view, "#councils-table section h2", "4ème")
    assert has_element?(view, "#council-row-#{ctx.cg.id}", "à planifier")

    view |> element("#filter-held") |> render_click()
    assert has_element?(view, "#filter-held[aria-current]")
    refute has_element?(view, "#council-row-#{ctx.cg.id}")

    view |> element("#filter-to_plan") |> render_click()
    assert has_element?(view, "#council-row-#{ctx.cg.id}")
  end

  describe "list and inline planning (Task 9)" do
    test "summary, statuses and CTAs", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
      assert has_element?(view, "#councils-summary", "à planifier")

      assert has_element?(
               view,
               "#council-row-#{ctx.cg.id} [data-status='to_plan']",
               "À planifier"
             )

      assert has_element?(view, "#plan-#{ctx.cg.id}")
    end

    test "a to-plan council that carries a date shows « — » instead", ctx do
      {:ok, _} =
        Councils.save_header(ctx.scope, ctx.cg, {:trimester, ctx.term}, %{
          "held_on" => "2025-10-14"
        })

      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
      assert has_element?(view, "#council-row-#{ctx.cg.id} [data-status='to_plan']")
      refute has_element?(view, "#council-row-#{ctx.cg.id}", "14/10")
      assert has_element?(view, "#council-row-#{ctx.cg.id} td.ta-num", "—")
    end

    test "« Planifier » saves date and time inline", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
      view |> element("#plan-#{ctx.cg.id}") |> render_click()

      view
      |> form("#plan-form-#{ctx.cg.id}", %{"plan" => %{"date" => "2025-10-14", "time" => "14:00"}})
      |> render_submit()

      assert has_element?(view, "#council-row-#{ctx.cg.id} [data-status='planned']", "Planifié")
      assert has_element?(view, "#council-row-#{ctx.cg.id}", "14:00")
      assert has_element?(view, "#council-row-#{ctx.cg.id}", "Préparer")
      assert has_element?(view, "#councils-summary", "1 planifié")
    end

    test "an invalid or missing time shows a form error", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")
      view |> element("#plan-#{ctx.cg.id}") |> render_click()

      view
      |> form("#plan-form-#{ctx.cg.id}", %{"plan" => %{"date" => "2025-10-14", "time" => ""}})
      |> render_submit()

      assert has_element?(view, "#plan-form-#{ctx.cg.id} [data-plan-error]")
      assert has_element?(view, "#council-row-#{ctx.cg.id} [data-status='to_plan']")
    end

    test "a locked council flashes", ctx do
      {:ok, _} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")

      render_submit(view, "plan", %{
        "plan" => %{"id" => ctx.cg.id, "date" => "2025-10-14", "time" => "14:00"}
      })

      assert render(view) =~ "Conseil verrouillé : bulletins publiés."
    end

    test "a held council links to its PV", ctx do
      {:ok, _} = Councils.hold(ctx.scope, ctx.cg, {:trimester, ctx.term})
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?term=#{ctx.term.id}")

      assert has_element?(
               view,
               "#council-row-#{ctx.cg.id} a[href^='/school/councils/#{ctx.cg.id}/print']",
               "Voir le PV"
             )
    end
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

  test "the header line shows only the parts that exist", ctx do
    {:ok, view, html} = live(ctx.conn, council_path(ctx.cg, ctx.term))
    refute html =~ ~r/Chaired by|Présidé par|Form master|PP :/

    view
    |> form("#council-header-form", %{council: %{chair: "M. Fotso", attendees: ""}})
    |> render_submit()

    html = render(view)
    assert html =~ ~r/(Chaired by|Présidé par) M\. Fotso/
    refute html =~ ~r/Form master|PP :|Chaired by —|Présidé par —/
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
    view |> element("#close-council") |> render_click()
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

  describe "council page (Task 10)" do
    defp path(ctx), do: council_path(ctx.cg, ctx.term)
    defp select(s), do: "#choice-#{s.id}"
    defp option(s, c), do: "#choice-#{s.id} option[value='#{c}']"

    defp choose(view, s, choice),
      do:
        view
        |> form("#choice-form-#{s.id}", %{"choice" => choice})
        |> render_change()

    test "header line, details disclosure and footnote", ctx do
      {:ok, view, html} = live(ctx.conn, path(ctx))
      assert has_element?(view, "#council h1", "Conseil de classe · 4e B")
      assert has_element?(view, "#council-details")
      refute html =~ ~s(id="council-details" open)
      assert html =~ "Les propositions viennent des règles de l&#39;établissement"
      assert has_element?(view, "#council a", "Conseils de classe")
    end

    test "rows show rank, average and the decision as one select; PV in the menu", ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))
      assert has_element?(view, "#council-row-#{ctx.dj.id}", "15,00")
      assert has_element?(view, "#council-row-#{ctx.tch.id} .text-error", "7,00")
      assert has_element?(view, "#council-row-#{ctx.dj.id} .badge", "Encouragements")
      assert has_element?(view, "#decisions-summary #count-encouragements", "1")
      assert has_element?(view, "#decisions-summary #count-avertissement_travail", "1")
      refute has_element?(view, "#decisions-summary #count-felicitations")

      assert has_element?(
               view,
               "#council-actions a[href^='/school/councils/#{ctx.cg.id}/print']",
               "Imprimer le PV"
             )
    end

    test "the select preselects the proposal; a change saves only the distinction choice",
         ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))
      assert has_element?(view, "#{option(ctx.tch, "avertissement_travail")}[selected]")
      refute has_element?(view, "#{option(ctx.tch, "tableau_honneur")}[selected]")

      view
      |> form("#decision-#{ctx.tch.id}", %{
        decision: %{conduct_warning: "avertissement_conduite", appreciation: "Doit se ressaisir"}
      })
      |> render_change()

      choose(view, ctx.tch, "tableau_honneur")
      assert has_element?(view, "#{option(ctx.tch, "tableau_honneur")}[selected]")
      refute has_element?(view, "#{option(ctx.tch, "avertissement_travail")}[selected]")
      assert has_element?(view, "#saved-#{ctx.tch.id}")
      assert has_element?(view, "#decisions-summary #count-tableau_honneur", "1")

      assert [d] = Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions
      assert d.distinction_choice == :tableau_honneur
      assert d.conduct_warning == :avertissement_conduite
      assert d.appreciation == "Doit se ressaisir"
    end

    test "the select locks after « Clôturer », and the server refuses choose when held", ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))
      view |> element("#close-council") |> render_click()
      view |> element("#confirm-hold") |> render_click()
      assert has_element?(view, "#close-council[disabled]", "Conseil clôturé")
      assert has_element?(view, "#{select(ctx.dj)}[disabled]")
      assert has_element?(view, "#reopen-council")

      render_click(view, "choose", %{"student_id" => ctx.dj.id, "choice" => "tableau_honneur"})
      assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions == []

      view |> element("#reopen-council") |> render_click()
      refute has_element?(view, "#{select(ctx.dj)}[disabled]")
    end

    test "a locked council refuses choose", ctx do
      {:ok, _} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
      {:ok, view, _} = live(ctx.conn, path(ctx))
      assert has_element?(view, "#{select(ctx.dj)}[disabled]")
      render_click(view, "choose", %{"student_id" => ctx.dj.id, "choice" => "tableau_honneur"})
      assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions == []
    end

    test "an unknown choice is refused", ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))
      render_click(view, "choose", %{"student_id" => ctx.dj.id, "choice" => "bogus"})
      assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).decisions == []
    end

    test "the header form saves an HTML time « 14:00 » and shows it in the eyebrow", ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))

      view
      |> form("#council-header-form", %{council: %{held_on: "2025-10-14", starts_at: "14:00"}})
      |> render_submit()

      assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).starts_at == ~T[14:00:00]
      assert has_element?(view, "#council header", "14:00")
    end

    test "an invalid time shows an error instead of crashing", ctx do
      {:ok, view, _} = live(ctx.conn, path(ctx))

      view
      |> form("#council-header-form", %{council: %{starts_at: "25:99"}})
      |> render_submit()

      assert render(view) =~ "Non enregistré"
      assert Councils.council(ctx.scope, ctx.cg, {:trimester, ctx.term}).starts_at == nil
    end
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

  describe "annual council (I4)" do
    test "the list has an Année tab", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils?period=annee")
      assert has_element?(view, "#term-annee.tab-active")
      assert has_element?(view, "#council-row-#{ctx.cg.id}")
    end

    test "the annual page proposes passage decisions and saves overrides", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/school/councils/#{ctx.cg.id}?period=annee")
      assert has_element?(view, "#passage-proposal-#{ctx.dj.id}", "Admis")
      assert has_element?(view, "#passage-proposal-#{ctx.tch.id}", "Redouble")

      view
      |> form("#decision-#{ctx.tch.id}", %{decision: %{passage_decision: "admis_rachat"}})
      |> render_change()

      assert [d] =
               Councils.council(ctx.scope, ctx.cg, {:annual, ctx.scope.current_academic_year}).decisions

      # the engine's proposal stays visible next to the council's choice
      assert has_element?(view, "#passage-proposal-#{ctx.tch.id}", "Redouble")
      refute has_element?(view, "#passage-proposal-#{ctx.tch.id}", "Admis par rachat")

      assert d.passage_decision == :admis_rachat
    end

    test "trimester pages have no passage column", ctx do
      {:ok, view, _} = live(ctx.conn, council_path(ctx.cg, ctx.term))
      refute has_element?(view, "#passage-proposal-#{ctx.dj.id}")
    end
  end
end
