defmodule TeacherAssistant.Academics.CombinedCourseTest do
  use TeacherAssistant.DataCase, async: true
  require Ash.Query
  alias TeacherAssistant.Academics.{CombinedCourse, ProgressionPlan}
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{head: head, ws: ws, year: year, scope: scope}
  end

  test "creates a combined course", %{head: head, year: year, scope: scope} do
    {:ok, c} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Mathématiques",
        label: "Maths · 1A MACO+MENU",
        academic_year_id: year.id,
        teacher_user_id: head.id
      })
      |> Ash.create(scope: scope)

    assert c.subject == "Mathématiques"
    assert c.teacher_user_id == head.id
  end

  test "Curriculum.combine_course/1 rejects contexts from two different schools", %{
    year: year,
    scope: scope
  } do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "1ère A", level: "1ère"})

    other_head = TeacherFixtures.user_fixture()

    {:ok, other_ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other_head}, %{
        name: "Autre lycée"
      })

    other_scope = school_scope(other_head, other_ws)

    {:ok, other_year} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, other_cg} =
      Enrollment.create_class_group(other_scope, other_year, %{label: "1ère A", level: "1ère"})

    # One teacher, an active member of BOTH schools, with a context in each —
    # so `combine_course/2`'s teacher/subject/count guards all pass and the
    # call actually reaches `CombinedCourse`'s `:combine` action instead of
    # being rejected upfront by `validate_same_teacher/1`.
    teacher = TeacherFixtures.user_fixture()
    _ = TeacherFixtures.member_scope_fixture(scope, %{user: teacher, roles: [:teacher]})
    _ = TeacherFixtures.member_scope_fixture(other_scope, %{user: teacher, roles: [:teacher]})

    {:ok, tc_a} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Mathématiques"})

    {:ok, tc_b} =
      Curriculum.assign_teacher(other_scope, other_cg, teacher, %{subject: "Mathématiques"})

    assert {:error, _} = Curriculum.combine_course(scope, [tc_a, tc_b])

    # Nothing was written in either tenant: no CombinedCourse, no
    # ProgressionPlan tied to one, and neither context got stamped.
    assert CombinedCourse
           |> Ash.Query.for_read(:read)
           |> Ash.read!(scope: scope) ==
             []

    assert CombinedCourse
           |> Ash.Query.for_read(:read)
           |> Ash.read!(scope: other_scope) == []

    assert ProgressionPlan
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(not is_nil(combined_course_id))
           |> Ash.read!(scope: scope) == []

    assert ProgressionPlan
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(not is_nil(combined_course_id))
           |> Ash.read!(scope: other_scope) == []

    assert {:ok, reloaded_tc_a} = Curriculum.get_teaching_context(scope, tc_a.id)
    assert {:ok, reloaded_tc_b} = Curriculum.get_teaching_context(other_scope, tc_b.id)
    assert is_nil(reloaded_tc_a.combined_course_id)
    assert is_nil(reloaded_tc_b.combined_course_id)
  end
end
