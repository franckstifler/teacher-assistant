defmodule TeacherAssistantWeb.School.CorrectionReviewLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, MarksFixtures, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference

  setup %{conn: conn} do
    world = MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)},
        %{student_id: world.s2.id, score: Decimal.new(8)}
      ])

    MarksFixtures.lock!(world, Date.add(Reference.today(), -1))
    censeur = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:vice_principal]})

    {:ok, c} =
      Assessment.request_correction(world.t, %{
        assessment_id: world.a.id,
        student_id: world.s1.id,
        requested_status: :graded,
        requested_score: Decimal.new(14),
        motive: :copie_mal_corrigee
      })

    conn =
      conn
      |> log_in_user(censeur.current_user)
      |> Plug.Conn.put_session(:workspace_id, world.head.current_workspace.id)

    Map.merge(world, %{conn: conn, censeur: censeur, c: c})
  end

  test "a teacher is sent back to the school home", ctx do
    conn = log_in_user(ctx.conn, ctx.t.current_user)
    assert {:error, {_, %{to: "/school"}}} = live(conn, ~p"/school/corrections/review")
  end

  test "the censeur reviews and approves a request", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    assert has_element?(view, "#nav-school-correction-review .badge", "1")
    assert has_element?(view, "#review-tab-pending")
    card = "#correction-card-#{ctx.c.id}"
    assert has_element?(view, card, "Awa")
    assert has_element?(view, card, "12 → 14")
    assert has_element?(view, card, "Copie mal corrigée")
    # The student's séquence average in the subject, before → after.
    assert has_element?(view, card, "Moyenne de séquence : 12 → 14")

    html =
      view |> form("#accept-form-#{ctx.c.id}", %{"accept" => %{"note" => ""}}) |> render_submit()

    assert html =~ "Correction acceptée : Awa"
    assert html =~ "Bulletin recalculé."
    refute has_element?(view, card)

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review?tab=decided")
    assert has_element?(view, "#decided-#{ctx.c.id}", "Acceptée")
  end

  test "pending requests are cards; refusing asks a reason first", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    assert has_element?(view, "#correction-card-#{ctx.c.id}", "12 → 14")
    refute has_element?(view, "#refuse-form-#{ctx.c.id}")
    view |> element("#refuse-#{ctx.c.id}") |> render_click()
    assert has_element?(view, "#refuse-form-#{ctx.c.id}")

    html =
      view |> form("#refuse-form-#{ctx.c.id}", %{"refusal" => %{"note" => ""}}) |> render_submit()

    assert html =~ "Indiquez le motif du refus."
    assert [_] = Assessment.list_corrections(ctx.censeur, :pending)

    html =
      view
      |> form("#refuse-form-#{ctx.c.id}", %{"refusal" => %{"note" => "Copie absente"}})
      |> render_submit()

    assert html =~ "Demande refusée."

    assert [%{status: :refused, decision_note: "Copie absente"}] =
             Assessment.list_corrections(ctx.censeur, :decided)

    [mark | _] =
      Assessment.list_marks(ctx.head, ctx.a) |> Enum.filter(&(&1.student_id == ctx.s1.id))

    assert Decimal.equal?(mark.score, 12)
  end

  test "a write made while an operator acted as the member names the operator (A6)", ctx do
    op = TeacherFixtures.admin_user_fixture(%{name: "Opératrice Ndzana"})
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), 30))

    :ok =
      Assessment.upsert_marks(impersonating(ctx.t, op), ctx.a, [
        %{student_id: ctx.s2.id, score: Decimal.new(11)}
      ])

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    journal = view |> element("#journal") |> render()
    assert journal =~ "(opérateur Opératrice Ndzana)"
  end

  test "the journal is on the same page under the cards", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    assert has_element?(view, "#journal")
    journal = view |> element("#journal") |> render()
    assert journal =~ "Devoir 1"
    assert journal =~ "2 notes"
    assert journal =~ "Correction demandée"
    assert journal =~ "Awa"
    assert journal =~ "Verrouillage"
    assert journal =~ "Système"
  end

  test "an accepted request carries its optional note", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")

    view
    |> form("#accept-form-#{ctx.c.id}", %{"accept" => %{"note" => "Vu avec la copie"}})
    |> render_submit()

    assert [%{status: :approved, decision_note: "Vu avec la copie"}] =
             Assessment.list_corrections(ctx.censeur, :decided)
  end

  test "a stale request says it must be redone", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), 30))
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))

    assert view
           |> form("#accept-form-#{ctx.c.id}", %{"accept" => %{"note" => ""}})
           |> render_submit() =~
             "La note a changé depuis la demande : demande à refaire."
  end

  test "a refusal note over 500 characters is named as the reason", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    view |> element("#refuse-#{ctx.c.id}") |> render_click()

    html =
      view
      |> form("#refuse-form-#{ctx.c.id}", %{"refusal" => %{"note" => String.duplicate("x", 501)}})
      |> render_submit()

    assert html =~ "La note dépasse 500 caractères."
    assert [_] = Assessment.list_corrections(ctx.censeur, :pending)
  end

  test "the title counts the requests; « Approuver / Refuser… » on each card", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    assert has_element?(view, "#correction-review h1", "Corrections à valider · 1")
    assert has_element?(view, "#correction-review header", "chaque décision est tracée")
    assert has_element?(view, "#accept-form-#{ctx.c.id} button[type=submit]", "Approuver")
    assert has_element?(view, "#refuse-#{ctx.c.id}", "Refuser…")
    # the journal folds, its summary counts
    assert has_element?(view, "details#journal summary", "Journal des notes")
    assert has_element?(view, "details#journal summary", "1 verrouillage")
    # no bulk action without an « erreur de saisie »
    refute has_element?(view, "#approve-typos")
  end

  test "« Approuver les N erreurs de saisie » approves those only, each traced", ctx do
    {:ok, typo} =
      Assessment.request_correction(ctx.t, %{
        assessment_id: ctx.a.id,
        student_id: ctx.s2.id,
        requested_status: :graded,
        requested_score: Decimal.new(18),
        motive: :erreur_saisie
      })

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    assert has_element?(view, "#approve-typos", "erreur de saisie")

    html = view |> element("#approve-typos") |> render_click()
    assert html =~ "1 correction approuvée"

    assert [%{id: id, status: :approved}] = Assessment.list_corrections(ctx.censeur, :decided)
    assert id == typo.id
    assert [%{id: pending_id}] = Assessment.list_corrections(ctx.censeur, :pending)
    assert pending_id == ctx.c.id
    refute has_element?(view, "#approve-typos")
  end
end
