defmodule TeacherAssistant.Academics.ClassGroupExamCodesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}

    {:ok, cg} =
      Enrollment.create_class_group(scope, year, %{label: "1ère F3", level: "1ère", serie: "F3"})

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    %{scope: scope, cg: cg, sg: sg}
  end

  test "admins and conduct managers set the codes, trimmed, empty as nil", %{
    scope: head,
    cg: cg,
    sg: sg
  } do
    assert {:ok, cg} =
             Enrollment.set_exam_codes(cg, %{exam_code: " PBF3 ", exam_center_code: "CR 8127"},
               scope: head
             )

    assert {cg.exam_code, cg.exam_center_code} == {"PBF3", "CR 8127"}

    assert {:ok, cg} =
             Enrollment.set_exam_codes(cg, %{exam_code: "", exam_center_code: "CR 9"}, scope: sg)

    assert {cg.exam_code, cg.exam_center_code} == {nil, "CR 9"}
  end

  test "a class whose form master left the school still gets its codes", %{
    scope: head,
    cg: cg
  } do
    fm = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
    {:ok, cg} = Enrollment.set_form_master(head, cg, fm.current_user.id)
    {:ok, m} = TeacherAssistant.Accounts.fetch_school_membership(head, fm.current_user)
    {:ok, _} = TeacherAssistant.Accounts.deactivate_member(head, m)

    assert {:ok, %{exam_center_code: "CR 8127"}} =
             Enrollment.set_exam_codes(cg, %{exam_center_code: "CR 8127"}, scope: head)
  end

  test "a teacher cannot set them", %{scope: head, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})

    assert {:error, %Ash.Error.Forbidden{}} =
             Enrollment.set_exam_codes(cg, %{exam_code: "PBF3"}, scope: teacher)
  end
end
