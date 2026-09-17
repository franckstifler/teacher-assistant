defmodule TeacherAssistant.Academics.TeachingContextCombinedTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, CombinedCourse}
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "1A", level: "1ère"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Mathématiques"})

    {:ok, course} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Mathématiques",
        label: "Maths · 1A MACO+MENU",
        workspace_id: ws.id,
        academic_year_id: year.id,
        teacher_user_id: head.id
      })
      |> Ash.create(authorize?: false)

    %{head: head, ws: ws, year: year, cg: cg, tc: tc, course: course}
  end

  test "a context defaults to no combined course", %{tc: tc} do
    assert tc.combined_course_id == nil
  end

  test "a context can be linked to a combined course", %{tc: tc, course: course} do
    {:ok, updated} =
      tc
      |> Ash.Changeset.for_update(:update, %{combined_course_id: course.id})
      |> Ash.update(authorize?: false)

    assert updated.combined_course_id == course.id
  end
end
