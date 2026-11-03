defmodule TeacherAssistant.EnrollmentFormMastersTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, a} = Enrollment.create_class_group(head, year, %{label: "6e Y", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(head, year, %{label: "6e Z", level: "6ème"})
    teacher_scope = TeacherFixtures.member_scope_fixture(head)

    %{
      head: head,
      year: year,
      a: a,
      b: b,
      teacher: teacher_scope.current_user,
      teacher_scope: teacher_scope
    }
  end

  test "sets several form masters at once", %{head: head, a: a, b: b, teacher: t} do
    assert {:ok, updated} =
             Enrollment.set_form_masters(head, [{a, t.id}, {b, head.current_user.id}])

    assert Enum.map(updated, & &1.form_master_user_id) == [t.id, head.current_user.id]
  end

  test "all or nothing: one refused class leaves the others unchanged", ctx do
    %{head: head, year: year, a: a, b: b, teacher: t} = ctx
    outsider = TeacherFixtures.user_fixture()

    assert {:error, _} = Enrollment.set_form_masters(head, [{a, t.id}, {b, outsider.id}])

    labels = Map.new(Enrollment.list_class_groups(head, year), &{&1.id, &1.form_master_user_id})
    assert labels[a.id] == nil
    assert labels[b.id] == nil
  end

  test "a plain teacher may not designate", %{teacher_scope: teacher_scope, a: a, teacher: t} do
    assert {:error, %Ash.Error.Forbidden{}} =
             Enrollment.set_form_masters(teacher_scope, [{a, t.id}])
  end
end
