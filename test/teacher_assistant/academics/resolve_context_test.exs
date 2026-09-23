defmodule TeacherAssistant.Academics.ResolveContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    maths =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    pct =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "PCT",
        level: "3ème",
        teacher: head
      })

    %{ws: ws, head: head, year: year, maths: maths, pct: pct}
  end

  test "returns the requested context when valid", %{ws: ws, year: year, pct: pct} do
    assert %{id: id} = Curriculum.resolve_current_context(ws, year, pct.id)
    assert id == pct.id
  end

  test "falls back to first (alphabetical) when id is nil/invalid/foreign", %{
    ws: ws,
    year: year,
    maths: maths
  } do
    assert Curriculum.resolve_current_context(ws, year, nil).id == maths.id
    assert Curriculum.resolve_current_context(ws, year, Ecto.UUID.generate()).id == maths.id

    %{workspace: other, head_user: other_head, year: oyear} =
      TeacherFixtures.setup_complete_school_fixture()

    foreign =
      TeacherFixtures.assigned_context_fixture(other, oyear, %{
        subject: "Maths",
        level: "3ème",
        teacher: other_head
      })

    assert Curriculum.resolve_current_context(ws, year, foreign.id).id == maths.id
  end

  test "returns nil when there is no active year or no contexts", %{ws: ws} do
    assert Curriculum.resolve_current_context(ws, nil, nil) == nil
    %{workspace: empty, year: y} = TeacherFixtures.setup_complete_school_fixture()

    assert Curriculum.resolve_current_context(empty, y, nil) == nil
  end
end
