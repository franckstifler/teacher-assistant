defmodule TeacherAssistantWeb.School.BulletinsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
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

    # Djoumessi 15, Tchinda not marked: entry incomplete; nothing in séquence 2
    [dj, tch] = Enrollment.list_roster(scope, cg)

    :ok =
      Assessment.upsert_marks(scope, a, [%{student_id: dj.student.id, score: Decimal.new(15)}])

    %{scope: scope, cg: cg, term: term, tc: tc, dj: dj, tch: tch}
  end

  defp bulletins_path(cg, term), do: ~p"/school/bulletins?class=#{cg.id}&period=trim:#{term.id}"

  defp conn_for(scope, user) do
    build_conn()
    |> log_in_user(user)
    |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)
  end

  test "lists the class with average, appreciation and distinction; first student in the panel",
       ctx do
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-status", "Brouillon")
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "15")
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "Encouragements")
    assert has_element?(view, "#student-panel", "Djoumessi Arnaud")
    assert has_element?(view, "#student-panel", "Maths · coef 4")
    assert has_element?(view, "#print-#{ctx.dj.student.id}[href*='/bulletin/print?period=trim']")
    assert has_element?(view, "#print-class")
  end

  test "selecting a student updates the side panel", ctx do
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    view |> element("#bulletins-row-#{ctx.tch.student.id} a[data-role=select]") |> render_click()
    assert has_element?(view, "#student-panel", "Tchinda Rodrigue")
  end

  test "incomplete entry asks for confirmation, then publishes", ctx do
    {:ok, _} = TeacherAssistant.Councils.hold(ctx.scope, ctx.cg, ctx.term)
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-rate", "25 %")
    view |> element("#publish") |> render_click()
    assert has_element?(view, "#publish-confirm", "Saisie incomplète")
    assert ReportCards.current_publication(ctx.scope, ctx.cg, {:trimester, ctx.term}) == nil

    view |> element("#confirm-publish") |> render_click()
    assert render(view) =~ "Bulletins publiés."
    assert has_element?(view, "#bulletins-status", "Publié le")
    assert ReportCards.current_publication(ctx.scope, ctx.cg, {:trimester, ctx.term})
  end

  test "withdraw needs a reason and is kept in the history", ctx do
    {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    view |> element("#ask-withdraw") |> render_click()

    view |> form("#withdraw-form", %{reason: "  "}) |> render_submit()
    assert has_element?(view, "#bulletins-status", "Publié le")

    view |> form("#withdraw-form", %{reason: "Note de maths erronée"}) |> render_submit()
    assert render(view) =~ "Bulletins dépubliés."
    assert has_element?(view, "#bulletins-status", "Brouillon")
    assert has_element?(view, "#bulletins-history", "Note de maths erronée")
  end

  test "a teacher of the class sees published periods only, read-only", ctx do
    %{teacher: teacher} =
      TeacherFixtures.school_teacher_fixture(ctx.scope, %{class_group: ctx.cg, subject: "SVT"})

    tconn = conn_for(ctx.scope, teacher)

    {:ok, view, _} = live(tconn, bulletins_path(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-not-published")
    refute has_element?(view, "#publish")
    refute has_element?(view, "#bulletins-rate")

    {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    {:ok, view, _} = live(tconn, bulletins_path(ctx.cg, ctx.term))
    assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}")
    refute has_element?(view, "#ask-withdraw")
    refute has_element?(view, "#publish")
  end

  test "someone with no class to see is sent home", ctx do
    other = TeacherFixtures.member_scope_fixture(ctx.scope)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(ctx.scope, other.current_user), ~p"/school/bulletins")
  end

  test "the menu has Bulletins for the head", ctx do
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    assert has_element?(view, "a[href='/school/bulletins']")
  end

  test "withdrawing from a stale page says it was already withdrawn", ctx do
    {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
    view |> element("#ask-withdraw") |> render_click()

    {:ok, _} = ReportCards.withdraw(ctx.scope, pub, "Another admin")
    view |> form("#withdraw-form", %{reason: "Me too"}) |> render_submit()

    assert render(view) =~ "Ces bulletins ont déjà été dépubliés."
    assert has_element?(view, "#bulletins-status", "Brouillon")
    assert has_element?(view, "#bulletins-history", "Another admin")
    refute has_element?(view, "#bulletins-history", "Me too")
  end

  describe "class council (I3)" do
    test "publishing waits for the held council; the distinction follows it", ctx do
      {:ok, _} =
        TeacherAssistant.Councils.set_decision(ctx.scope, ctx.cg, ctx.term, ctx.dj.student.id, %{
          "distinction_choice" => "tableau_honneur"
        })

      {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
      assert has_element?(view, "#publish[disabled]")
      assert has_element?(view, "#council-not-held", "Conseil de classe non tenu")
      assert has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "Tableau d")
      refute has_element?(view, "#bulletins-row-#{ctx.dj.student.id}", "Encouragements")

      {:ok, _} = TeacherAssistant.Councils.hold(ctx.scope, ctx.cg, ctx.term)
      {:ok, view, _} = live(ctx.conn, bulletins_path(ctx.cg, ctx.term))
      refute has_element?(view, "#publish[disabled]")
      refute has_element?(view, "#council-not-held")
    end
  end
end
