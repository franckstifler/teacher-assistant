defmodule TeacherAssistantWeb.RouterPauseTest do
  use TeacherAssistantWeb.ConnCase, async: true

  test "the personal teacher routes no longer exist, even with a flag" do
    refute Application.get_env(:teacher_assistant, :teacher_personal_routes)

    routes =
      TeacherAssistantWeb.Router.__routes__()
      |> Enum.map(& &1.path)
      |> Enum.filter(&String.starts_with?(&1, "/teacher"))
      |> Enum.sort()

    # The working class list a teacher prints from their course (spec 2026-10-31 §1).
    assert routes == [
             "/teacher/class-lists/print",
             "/teacher/contexts/:id/class-list/print",
             "/teacher/contexts/:id/marks",
             "/teacher/contexts/:id/marks/summary",
             "/teacher/contexts/:id/roster",
             "/teacher/select-context/:id"
           ]
  end
end
