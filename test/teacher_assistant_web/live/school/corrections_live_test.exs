defmodule TeacherAssistantWeb.School.CorrectionsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, MarksFixtures, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference

  setup %{conn: conn} do
    world = MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    MarksFixtures.lock!(world, Date.add(Reference.today(), -1))
    censeur = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:vice_principal]})

    conn =
      conn
      |> log_in_user(world.t.current_user)
      |> Plug.Conn.put_session(:workspace_id, world.head.current_workspace.id)

    Map.merge(world, %{conn: conn, censeur: censeur})
  end

  test "a teacher files a request for a locked mark", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")
    assert has_element?(view, "#new-correction-form option[value='#{ctx.a.id}'][selected]")
    assert has_element?(view, "#new-correction-form option[value='#{ctx.s1.id}']")

    html =
      view
      |> form("#new-correction-form", %{
        "correction" => %{
          "assessment_id" => ctx.a.id,
          "student_id" => ctx.s1.id,
          "value" => "14,5",
          "motive" => "erreur_saisie"
        }
      })
      |> render_submit()

    assert html =~
             "Demande envoyée à #{TeacherAssistant.Accounts.User.display_name(ctx.censeur.current_user)} (censeur)."

    assert [c] = Assessment.list_my_corrections(ctx.t)
    assert Decimal.equal?(c.requested_score, Decimal.new("14.5"))
    assert has_element?(view, "#correction-#{c.id}", "12 → 14,5")
    assert has_element?(view, "#correction-#{c.id}", "En attente")
  end

  test "an invalid value is refused inline and nothing is filed", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")

    html =
      view
      |> form("#new-correction-form", %{
        "correction" => %{
          "assessment_id" => ctx.a.id,
          "student_id" => ctx.s1.id,
          "value" => "douze",
          "motive" => "erreur_saisie"
        }
      })
      |> render_submit()

    assert html =~ "Note invalide"
    assert Assessment.list_my_corrections(ctx.t) == []
  end

  test "only locked assessments of the teacher's courses are offered", ctx do
    [_, seq2 | _] = TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year)
    {:ok, open_a} = Assessment.create_assessment(ctx.t, ctx.tc, seq2, %{label: "Ouvert"})
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new")
    assert has_element?(view, "#new-correction-form option[value='#{ctx.a.id}']")
    refute has_element?(view, "#new-correction-form option[value='#{open_a.id}']")
  end

  test "decisions show on the list and are marked seen", ctx do
    {:ok, c} =
      Assessment.request_correction(ctx.t, %{
        assessment_id: ctx.a.id,
        student_id: ctx.s1.id,
        requested_status: :absent,
        motive: :reclamation_eleve
      })

    {:ok, _} = Assessment.approve_correction(ctx.censeur, c)
    assert Assessment.unseen_decisions_count(ctx.t) == 1

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
    assert has_element?(view, "#correction-#{c.id}", "Acceptée")
    assert has_element?(view, "#correction-#{c.id}", "12 → abs")
    assert Assessment.unseen_decisions_count(ctx.t) == 0
  end

  test ":index hides the form until « Nouvelle demande »", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
    refute has_element?(view, "#new-correction-form")
    view |> element("#new-correction-button") |> render_click()
    assert_patch(view, ~p"/school/corrections/new")
    assert has_element?(view, "#new-correction-form")
  end

  test "the student option shows the current mark; only four motives", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")

    assert has_element?(
             view,
             "#new-correction-form option[value='#{ctx.s1.id}']",
             "— note actuelle 12"
           )

    assert has_element?(view, "input[name='correction[motive]'][value='copie_retrouvee']")
    refute has_element?(view, "input[name='correction[motive]'][value='reclamation_eleve']")
  end

  test "a sent request closes the form", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")

    view
    |> form("#new-correction-form", %{
      "correction" => %{
        "assessment_id" => ctx.a.id,
        "student_id" => ctx.s1.id,
        "value" => "14",
        "motive" => "erreur_saisie"
      }
    })
    |> render_submit()

    assert_patch(view, ~p"/school/corrections")
    refute has_element?(view, "#new-correction-form")
  end

  test "without a single censeur the flash names no one", ctx do
    TeacherFixtures.member_scope_fixture(ctx.head, %{roles: [:vice_principal]})
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")

    html =
      view
      |> form("#new-correction-form", %{
        "correction" => %{
          "assessment_id" => ctx.a.id,
          "student_id" => ctx.s1.id,
          "value" => "14",
          "motive" => "erreur_saisie"
        }
      })
      |> render_submit()

    assert html =~ "Demande envoyée au censeur."
  end

  test "a decision shows who decided and the note; an empty note adds no separator", ctx do
    {:ok, c1} = request(ctx, ctx.s1)
    {:ok, _} = Assessment.refuse_correction(ctx.censeur, c1, "Joindre la copie")
    {:ok, c2} = request(ctx, ctx.s2)
    {:ok, _} = Assessment.approve_correction(ctx.censeur, c2)

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
    assert has_element?(view, "#correction-#{c1.id}", "Joindre la copie")
    assert has_element?(view, "#correction-#{c1.id}", "Refusée")
    assert has_element?(view, "#correction-#{c2.id} [data-role='decision']", "Par ")
    refute render(element(view, "#correction-#{c2.id} [data-role='decision']")) =~ "·"
  end

  defp request(ctx, student) do
    Assessment.request_correction(ctx.t, %{
      assessment_id: ctx.a.id,
      student_id: student.id,
      requested_status: :graded,
      requested_score: Decimal.new(14),
      motive: :erreur_saisie
    })
  end
end
