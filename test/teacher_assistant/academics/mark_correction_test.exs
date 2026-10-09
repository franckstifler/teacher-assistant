defmodule TeacherAssistant.Academics.MarkCorrectionTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference
  import TeacherAssistant.MarksFixtures, only: [lock!: 2]

  setup do
    world = TeacherAssistant.MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    censeur = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:vice_principal]})
    other = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:teacher]})
    Map.merge(world, %{censeur: censeur, other: other})
  end

  defp lock(ctx), do: lock!(ctx, Date.add(Reference.today(), -1))
  defp unlock(ctx), do: lock!(ctx, Date.add(Reference.today(), 30))

  defp req(ctx, attrs) do
    Map.merge(
      %{
        assessment_id: ctx.a.id,
        student_id: ctx.s1.id,
        requested_status: :graded,
        motive: :erreur_saisie
      },
      Map.new(attrs)
    )
  end

  defp mark_of(ctx) do
    ctx.head |> Assessment.list_marks(ctx.a) |> Enum.find(&(&1.student_id == ctx.s1.id))
  end

  test "the course teacher requests a correction on a locked mark", ctx do
    lock(ctx)

    assert {:ok, c} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))

    assert c.status == :pending and c.current_status == :graded
    assert Decimal.equal?(c.current_score, 12)
    assert c.requester_user_id == ctx.t.current_user.id

    assert [%{action: :correction_demandee, mark_correction_id: id} | _] =
             Assessment.list_mark_events(ctx.head)

    assert id == c.id
    assert [%{id: ^id}] = Assessment.list_my_corrections(ctx.t)
    assert Assessment.pending_corrections_count(ctx.censeur) == 1
  end

  test "a correction can target a blank mark and ask for an absence", ctx do
    lock(ctx)

    assert {:ok, c} =
             Assessment.request_correction(
               ctx.t,
               req(ctx, student_id: ctx.s2.id, requested_status: :absent)
             )

    assert c.current_status == nil
  end

  test "requests are refused on open assessments, from another teacher, twice, or unchanged",
       ctx do
    assert {:error, _} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))

    lock(ctx)

    assert {:error, _} =
             Assessment.request_correction(ctx.other, req(ctx, requested_score: Decimal.new(14)))

    assert {:error, _} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(12)))

    assert {:error, _} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(21)))

    assert {:ok, _} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))

    assert {:error, _} =
             Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(15)))
  end

  test "approval writes the mark and journals it; only admins decide", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    assert Assessment.can_decide_corrections?(ctx.censeur)
    refute Assessment.can_decide_corrections?(ctx.t)
    assert {:error, _} = Assessment.approve_correction(ctx.t, c)

    assert {:ok, %{status: :approved} = done} = Assessment.approve_correction(ctx.censeur, c)
    assert done.decider_user_id == ctx.censeur.current_user.id and done.decided_at
    assert Decimal.equal?(mark_of(ctx).score, 14)

    assert %{mark_correction_id: id, actor_user_id: actor} =
             Enum.find(
               Assessment.list_mark_events(ctx.head),
               &(&1.action == :correction_approuvee)
             )

    assert id == c.id and actor == ctx.censeur.current_user.id
    assert {:error, _} = Assessment.approve_correction(ctx.censeur, done)
  end

  test "approving a blank request deletes the mark", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_status: nil))
    {:ok, _} = Assessment.approve_correction(ctx.censeur, c)
    assert mark_of(ctx) == nil
  end

  test "a stale request cannot be approved", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    unlock(ctx)
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    lock(ctx)
    assert {:error, error} = Assessment.approve_correction(ctx.censeur, c)
    assert Exception.message(error) =~ "stale"
    assert Decimal.equal?(mark_of(ctx).score, 9)
    assert [%{status: :pending}] = Assessment.list_corrections(ctx.censeur, :pending)
  end

  test "refusing leaves the mark and journals the refusal", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    assert {:ok, %{status: :refused}} = Assessment.refuse_correction(ctx.censeur, c)
    assert Decimal.equal?(mark_of(ctx).score, 12)
    assert [%{action: :correction_refusee} | _] = Assessment.list_mark_events(ctx.head)
    assert [%{status: :refused}] = Assessment.list_corrections(ctx.censeur, :decided)
  end

  test "the teacher sees decisions until they visit", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    assert Assessment.unseen_decisions_count(ctx.t) == 0
    {:ok, _} = Assessment.refuse_correction(ctx.censeur, c)
    assert Assessment.unseen_decisions_count(ctx.t) == 1
    :ok = Assessment.mark_corrections_seen(ctx.t)
    assert Assessment.unseen_decisions_count(ctx.t) == 0
  end

  test "requests are private to their author and the admins", ctx do
    lock(ctx)
    {:ok, _} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    assert Assessment.list_my_corrections(ctx.other) == []
    assert Assessment.list_corrections(ctx.other, :pending) == []
  end

  test "a correction id on a direct write does not unlock", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    mark = mark_of(ctx)

    for scope <- [ctx.t, ctx.censeur] do
      assert {:error, _} =
               mark
               |> Ash.Changeset.for_update(:update, %{score: Decimal.new(3)},
                 scope: scope,
                 context: %{mark_correction_id: c.id, mark_correction_deciding?: true}
               )
               |> Ash.update()
    end
  end

  test "a decision taken from a stale page cannot overturn another", ctx do
    lock(ctx)
    {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
    {:ok, _} = Assessment.refuse_correction(ctx.head, c)

    assert {:error, _} = Assessment.approve_correction(ctx.censeur, c)
    assert Decimal.equal?(mark_of(ctx).score, 12)
    assert [%{status: :refused}] = Assessment.list_corrections(ctx.censeur, :decided)

    {:ok, c2} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(15)))
    {:ok, _} = Assessment.approve_correction(ctx.head, c2)
    assert {:error, _} = Assessment.refuse_correction(ctx.censeur, c2)
    assert Decimal.equal?(mark_of(ctx).score, 15)

    assert Enum.count(Assessment.list_mark_events(ctx.head), &(&1.action == :correction_refusee)) ==
             1
  end
  describe "decision note and motives" do
    setup ctx do
      lock(ctx)
      :ok
    end

    test "refusal stores the censeur's note", ctx do
      {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))

      {:ok, refused} =
        Assessment.refuse_correction(ctx.censeur, c, "  Joindre la copie au dossier  ")

      assert refused.decision_note == "Joindre la copie au dossier"
      assert refused.decider.id == ctx.censeur.current_user.id
    end

    test "approval without a note leaves it nil", ctx do
      {:ok, c} = Assessment.request_correction(ctx.t, req(ctx, requested_score: Decimal.new(14)))
      {:ok, approved} = Assessment.approve_correction(ctx.censeur, c)
      assert approved.decision_note == nil
    end
  end

  test "offered motives are the mockup's four; old values still label" do
    alias TeacherAssistant.Academics.MarkCorrectionMotive

    assert MarkCorrectionMotive.offered() ==
             [:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul]

    assert MarkCorrectionMotive.label(:copie_retrouvee) == "Copie retrouvée"
    assert MarkCorrectionMotive.label(:note_rattrapage) == "Rattrapage"
    assert MarkCorrectionMotive.label(:reclamation_eleve) == "Réclamation de l'élève"
  end
end
