defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    %{head: head, ws: ws, year: year, cg: cg, scope: scope}
  end

  test "two teachers can hold the same subject/level on different classes", %{
    year: year,
    scope: scope
  } do
    ctx1 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{subject: "Maths", level: "6ème"})

    ctx2 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{subject: "Maths", level: "6ème"})

    assert ctx1.class_group_id != ctx2.class_group_id
    assert ctx1.teacher_user_id != ctx2.teacher_user_id
  end

  test "one teacher per subject per class", %{
    ws: ws,
    year: year,
    cg: cg,
    head: head,
    scope: scope
  } do
    _ctx1 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        class_group: cg,
        teacher: head,
        subject: "Maths"
      })

    u2 = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(ws, head, %{email: to_string(u2.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, u2)

    assert {:error, _} = Curriculum.assign_teacher(scope, cg, u2, %{subject: "Maths"})
  end

  test "a teaching context requires a teacher and a class group" do
    %{workspace: ws, year: year} = TeacherFixtures.setup_complete_school_fixture()

    assert {:error, %Ash.Error.Invalid{}} =
             TeacherAssistant.Academics.TeachingContext
             |> Ash.Changeset.for_create(:create, %{
               subject: "Maths",
               level: "3ème",
               academic_year_id: year.id
             })
             |> Ash.Changeset.set_tenant(ws.id)
             |> Ash.create()
  end
end
