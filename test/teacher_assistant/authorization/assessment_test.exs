defmodule TeacherAssistant.Authorization.AssessmentTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Assessment, Organization, Scope}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    %{teaching_context: tc, class_group: cg, scope: owner} = school_teacher_fixture(head)
    other = member_scope_fixture(head, %{roles: [:teacher]})
    [seq | _] = Organization.list_sequences(head, year)
    %{ws: ws, head: head, owner: owner, other: other, tc: tc, tc_class_group: cg, seq: seq}
  end

  test "the owner and admins create assessments; another teacher cannot", ctx do
    assert {:ok, a} = Assessment.create_assessment(ctx.owner, ctx.tc, ctx.seq, %{label: "D1"})
    assert {:ok, _} = Assessment.create_assessment(ctx.head, ctx.tc, ctx.seq, %{label: "D2"})
    assert_forbidden(Assessment.create_assessment(ctx.other, ctx.tc, ctx.seq, %{label: "D3"}))
    assert length(Assessment.list_assessments(ctx.other, ctx.tc, ctx.seq)) == 2
    assert a.teaching_context_id == ctx.tc.id
  end

  test "marks are refused in an unverified school, even for the owner" do
    %{scope: head, year: year} = setup_complete_school_fixture(%{verified: false})
    %{teaching_context: tc, scope: owner} = school_teacher_fixture(head)
    [seq | _] = Organization.list_sequences(head, year)
    assert_forbidden(Assessment.create_assessment(owner, tc, seq, %{label: "D1"}))
  end

  test "outsiders and actor-less calls are refused", ctx do
    outsider = %Scope{current_user: user_fixture(), current_workspace: ctx.ws}
    assert_forbidden(Assessment.create_assessment(outsider, ctx.tc, ctx.seq, %{label: "X"}))

    assert_forbidden(
      Assessment.create_assessment(%Scope{current_workspace: ctx.ws}, ctx.tc, ctx.seq, %{
        label: "Y"
      })
    )
  end

  describe "upsert_marks" do
    setup ctx do
      {:ok, a} = Assessment.create_assessment(ctx.owner, ctx.tc, ctx.seq, %{label: "D1"})

      {:ok, %{enrollment: e}} =
        TeacherAssistant.Enrollment.enroll_new(ctx.head, ctx.tc_class_group, %{
          full_name: "Awa",
          sex: :f
        })

      %{a: a, entries: [%{student_id: e.student_id, score: Decimal.new(12)}]}
    end

    test "another teacher cannot write marks on the owner's assessment", ctx do
      assert_forbidden(Assessment.upsert_marks(ctx.other, ctx.a, ctx.entries))
      assert Assessment.list_marks(ctx.owner, ctx.a) == []
      assert :ok = Assessment.upsert_marks(ctx.owner, ctx.a, ctx.entries)
    end

    test "the owner cannot write marks once the school is rejected", ctx do
      operator = admin_user_fixture()
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.head)

      {:ok, _} =
        TeacherAssistant.Accounts.reject_school(profile, operator.id, "x", actor: operator)

      assert_forbidden(Assessment.upsert_marks(ctx.owner, ctx.a, ctx.entries))
      assert Assessment.list_marks(ctx.owner, ctx.a) == []
    end
  end
end
