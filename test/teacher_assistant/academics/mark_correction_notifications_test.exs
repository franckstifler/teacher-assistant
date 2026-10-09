defmodule TeacherAssistant.Academics.MarkCorrectionNotificationsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Notifications, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference
  import TeacherAssistant.MarksFixtures, only: [lock!: 2]

  setup do
    world = TeacherAssistant.MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    censeur = TeacherFixtures.member_scope_fixture(world.head, %{roles: [:vice_principal]})
    # Joining the school notified the admins (:member_joined); start from a clean bell.
    Notifications.mark_all_read(world.head)
    Notifications.mark_all_read(censeur)
    Map.put(world, :censeur, censeur)
  end

  defp lock(ctx), do: lock!(ctx, Date.add(Reference.today(), -1))
  defp unlock(ctx), do: lock!(ctx, Date.add(Reference.today(), 30))

  defp request(ctx, scope \\ nil, assessment \\ nil, score \\ 14) do
    Assessment.request_correction(scope || ctx.t, %{
      assessment_id: (assessment || ctx.a).id,
      student_id: ctx.s1.id,
      requested_status: :graded,
      requested_score: Decimal.new(score),
      motive: :erreur_saisie
    })
  end

  test "a request notifies the Proviseur and the Censeur, not the teacher", ctx do
    lock(ctx)
    {:ok, _} = request(ctx)

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.censeur)
    assert n.kind == :correction_requested
    assert n.link == "/school/corrections/review"
    teacher = ctx.t.current_user

    assert n.params == %{
             "teacher" => to_string(teacher.name || teacher.email),
             "student" => "Awa",
             "subject" => "Maths",
             "class" => ctx.cg.label,
             "assessment" => "Devoir 1",
             "change" => "12 → 14"
           }

    assert %{unread: 1} = Notifications.bell(ctx.head)
    assert %{unread: 0} = Notifications.bell(ctx.t)
  end

  test "approving and refusing notify the requesting teacher with the decision", ctx do
    lock(ctx)
    {:ok, c} = request(ctx)
    {:ok, _} = Assessment.approve_correction(ctx.censeur, c)

    assert %{latest: [n]} = Notifications.bell(ctx.t)
    assert n.kind == :correction_decided
    assert n.link == "/school/corrections"
    assert %{"decision" => "approved", "student" => "Awa", "assessment" => "Devoir 1"} = n.params

    {:ok, c2} = request(ctx, nil, nil, 15)
    {:ok, _} = Assessment.refuse_correction(ctx.head, c2)

    assert %{unread: 2, latest: [%{params: %{"decision" => "refused"}} | _]} =
             Notifications.bell(ctx.t)

    # Two requests reached the Censeur; their own decision did not.
    assert %{unread: 2} = Notifications.bell(ctx.censeur)
  end

  test "a stale approval notifies nobody", ctx do
    lock(ctx)
    {:ok, c} = request(ctx)
    unlock(ctx)
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    lock(ctx)

    assert {:error, _} = Assessment.approve_correction(ctx.censeur, c)
    assert %{unread: 0} = Notifications.bell(ctx.t)
  end

  test "an admin who requests on their own course is not notified of it", ctx do
    {:ok, tc} =
      Curriculum.assign_teacher(ctx.head, ctx.cg, ctx.head.current_user, %{subject: "SVT"})

    {:ok, a} = Assessment.create_assessment(ctx.head, tc, ctx.seq, %{label: "Interro SVT"})
    :ok = Assessment.upsert_marks(ctx.head, a, [%{student_id: ctx.s1.id, score: Decimal.new(9)}])
    lock(ctx)

    {:ok, _} = request(ctx, ctx.head, a)
    assert %{unread: 0} = Notifications.bell(ctx.head)
    assert %{unread: 1} = Notifications.bell(ctx.censeur)
  end
end
