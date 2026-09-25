defmodule TeacherAssistant.Academics.CombinedCourseTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.CombinedCourse
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

  test "creates a combined course", %{head: head, ws: ws, year: year} do
    {:ok, c} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Mathématiques",
        label: "Maths · 1A MACO+MENU",
        academic_year_id: year.id,
        teacher_user_id: head.id
      })
      |> Ash.Changeset.set_tenant(ws.id)
      |> Ash.create(authorize?: false)

    assert c.subject == "Mathématiques"
    assert c.teacher_user_id == head.id
  end

  test "Curriculum.combine_course/1 rejects contexts from two different schools", %{
    head: head,
    ws: ws,
    year: year,
    scope: scope
  } do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "1ère A", level: "1ère"})
    {:ok, tc_a} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})

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

    {:ok, tc_b} =
      Curriculum.assign_teacher(other_scope, other_cg, other_head, %{subject: "Mathématiques"})

    assert {:error, _} = Curriculum.combine_course(scope, [tc_a, tc_b])

    assert CombinedCourse
           |> Ash.Query.for_read(:read)
           |> Ash.Query.set_tenant(ws.id)
           |> Ash.read!() ==
             []

    assert CombinedCourse
           |> Ash.Query.for_read(:read)
           |> Ash.Query.set_tenant(other_ws.id)
           |> Ash.read!() == []
  end
end
