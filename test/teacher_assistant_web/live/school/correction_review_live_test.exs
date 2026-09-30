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
    assert has_element?(view, "#pending-#{ctx.c.id}", "Awa")
    assert has_element?(view, "#pending-#{ctx.c.id}", "12 → 14")

    view |> element("#pending-#{ctx.c.id}") |> render_click()
    detail = view |> element("#correction-detail") |> render()
    assert detail =~ "Copie mal corrigée"
    # The student's séquence average in the subject, before → after.
    assert detail =~ "12 → 14"

    html = view |> element("#approve-correction") |> render_click()
    assert html =~ "Correction approuvée."
    refute has_element?(view, "#pending-#{ctx.c.id}")

    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review?tab=decided")
    assert has_element?(view, "#decided-#{ctx.c.id}", "Approuvée")
  end

  test "the censeur refuses a request", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    view |> element("#pending-#{ctx.c.id}") |> render_click()
    assert view |> element("#refuse-correction") |> render_click() =~ "Correction refusée."

    [mark | _] =
      Assessment.list_marks(ctx.head, ctx.a) |> Enum.filter(&(&1.student_id == ctx.s1.id))

    assert Decimal.equal?(mark.score, 12)
  end

  test "a stale request says it must be redone", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review")
    view |> element("#pending-#{ctx.c.id}") |> render_click()
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), 30))
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))

    assert view |> element("#approve-correction") |> render_click() =~
             "La note a changé depuis la demande : demande à refaire."
  end

  test "the journal lists saves, requests and the lock", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/review?tab=journal")
    journal = view |> element("#journal") |> render()
    assert journal =~ "Devoir 1"
    assert journal =~ "2 notes"
    assert journal =~ "Correction demandée"
    assert journal =~ "Awa"
    assert journal =~ "Verrouillage"
    assert journal =~ "Système"
  end
end
