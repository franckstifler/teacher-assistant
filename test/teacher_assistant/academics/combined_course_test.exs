defmodule TeacherAssistant.Academics.CombinedCourseTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Organization.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{head: head, ws: ws, year: year}
  end

  test "creates a combined course", %{head: head, ws: ws, year: year} do
    {:ok, c} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Mathématiques",
        label: "Maths · 1A MACO+MENU",
        workspace_id: ws.id,
        academic_year_id: year.id,
        teacher_user_id: head.id
      })
      |> Ash.create(authorize?: false)

    assert c.subject == "Mathématiques"
    assert c.teacher_user_id == head.id
  end

  test "Curriculum.combine_course/1 rejects contexts from two different schools", %{
    head: head,
    ws: ws,
    year: year
  } do
    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "1ère A", level: "1ère"})
    {:ok, tc_a} = Curriculum.assign_teacher(cg, head, %{subject: "Mathématiques"})

    other_head = TeacherFixtures.user_fixture()
    {:ok, other_ws} = Organization.create_school(other_head, %{name: "Autre lycée"})

    {:ok, other_year} =
      Organization.create_academic_year(other_ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, other_cg} =
      Enrollment.create_class_group(other_ws, other_year, %{label: "1ère A", level: "1ère"})

    {:ok, tc_b} = Curriculum.assign_teacher(other_cg, other_head, %{subject: "Mathématiques"})

    assert {:error, :workspace_mismatch} = Curriculum.combine_course([tc_a, tc_b])
  end
end
