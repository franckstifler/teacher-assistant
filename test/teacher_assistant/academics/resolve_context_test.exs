defmodule TeacherAssistant.Academics.ResolveContextTest do
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

    {:ok, maths} =
      Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})

    {:ok, pct} =
      Academics.create_teaching_context(ws, year, %{subject: "PCT", level: "3ème", subsystem: :francophone, weekly_hours: 4})

    %{ws: ws, year: year, maths: maths, pct: pct}
  end

  test "returns the requested context when valid", %{ws: ws, year: year, pct: pct} do
    assert %{id: id} = Academics.resolve_current_context(ws, year, pct.id)
    assert id == pct.id
  end

  test "falls back to first (alphabetical) when id is nil/invalid/foreign", %{ws: ws, year: year, maths: maths} do
    assert Academics.resolve_current_context(ws, year, nil).id == maths.id
    assert Academics.resolve_current_context(ws, year, Ecto.UUID.generate()).id == maths.id

    other = TeacherFixtures.workspace_fixture()
    {:ok, oyear} = Academics.create_academic_year(other, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, foreign} = Academics.create_teaching_context(other, oyear, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
    assert Academics.resolve_current_context(ws, year, foreign.id).id == maths.id
  end

  test "returns nil when there is no active year or no contexts", %{ws: ws} do
    assert Academics.resolve_current_context(ws, nil, nil) == nil
    empty = TeacherFixtures.workspace_fixture()
    {:ok, y} = Academics.create_academic_year(empty, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    assert Academics.resolve_current_context(empty, y, nil) == nil
  end
end
