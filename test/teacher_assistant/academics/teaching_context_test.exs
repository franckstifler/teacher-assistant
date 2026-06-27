defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{ws: ws, year: year}
  end

  test "create and list a teaching context", %{ws: ws, year: year} do
    assert {:ok, ctx} =
             Academics.create_teaching_context(ws, year, %{
               subject: "Mathematics",
               level: "Form 1",
               subsystem: :anglophone,
               weekly_hours: 4
             })

    assert ctx.subject == "Mathematics"
    assert [listed] = Academics.list_teaching_contexts(ws, year)
    assert listed.id == ctx.id
  end
end
