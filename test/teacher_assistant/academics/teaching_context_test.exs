defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    %{head: head, ws: ws, year: year, cg: cg}
  end

  test "two teachers can hold the same subject/level on different classes", %{ws: ws, year: year} do
    ctx1 = TeacherFixtures.assigned_context_fixture(ws, year, %{subject: "Maths", level: "6ème"})
    ctx2 = TeacherFixtures.assigned_context_fixture(ws, year, %{subject: "Maths", level: "6ème"})

    assert ctx1.class_group_id != ctx2.class_group_id
    assert ctx1.teacher_user_id != ctx2.teacher_user_id
  end

  test "one teacher per subject per class", %{ws: ws, year: year, cg: cg, head: head} do
    _ctx1 =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        class_group: cg,
        teacher: head,
        subject: "Maths"
      })

    u2 = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(ws, head, %{email: to_string(u2.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, u2)

    assert {:error, _} = Curriculum.assign_teacher(cg, u2, %{subject: "Maths"})
  end

  test "create accepts annual_hours and count targets", %{ws: ws, year: year} do
    {:ok, ctx} =
      TeacherAssistant.Academics.TeachingContext
      |> Ash.Changeset.for_create(:create, %{
        subject: "Physique",
        level: "5ème",
        subsystem: :francophone,
        weekly_hours: 4,
        annual_hours: Decimal.new("100"),
        target_module_count: 4,
        target_lesson_count: 21,
        workspace_id: ws.id,
        academic_year_id: year.id
      })
      |> Ash.create()

    assert Decimal.equal?(ctx.annual_hours, Decimal.new("100"))
    assert ctx.target_module_count == 4
    assert ctx.target_lesson_count == 21
  end

  test "update_teaching_context persists targets for an owned context", %{ws: ws, year: year} do
    ctx = TeacherFixtures.assigned_context_fixture(ws, year, %{subject: "Maths", level: "6ème"})

    {:ok, ctx} =
      Curriculum.update_teaching_context(ctx.id, ws, %{
        annual_hours: Decimal.new("75"),
        target_lesson_count: 18
      })

    assert Decimal.equal?(ctx.annual_hours, Decimal.new("75"))
    assert ctx.target_lesson_count == 18
  end

  test "update_teaching_context rejects a context from another workspace", %{
    ws: ws,
    year: year
  } do
    ctx = TeacherFixtures.assigned_context_fixture(ws, year, %{subject: "Maths", level: "6ème"})
    %{workspace: other} = TeacherFixtures.school_fixture()

    assert {:error, :not_found} =
             Curriculum.update_teaching_context(ctx.id, other, %{annual_hours: Decimal.new("50")})
  end
end
