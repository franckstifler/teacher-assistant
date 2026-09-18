defmodule TeacherAssistant.Academics.CombinedCourseTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.{Academics, TeacherFixtures}

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    %{head: head, ws: ws, year: year}
  end

  test "creates a combined course", %{head: head, ws: ws, year: year} do
    {:ok, c} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{subject: "Mathématiques", label: "Maths · 1A MACO+MENU", workspace_id: ws.id, academic_year_id: year.id, teacher_user_id: head.id})
      |> Ash.create(authorize?: false)

    assert c.subject == "Mathématiques"
    assert c.teacher_user_id == head.id
  end
end
