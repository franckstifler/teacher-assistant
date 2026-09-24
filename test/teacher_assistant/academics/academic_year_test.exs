defmodule TeacherAssistant.Academics.AcademicYearTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws} = TeacherFixtures.school_fixture()
    %{ws: ws}
  end

  test "create + current academic year", %{ws: ws} do
    assert {:ok, year} =
             Organization.create_academic_year(ws, %{
               name: "2025-2026",
               start_date: ~D[2025-09-08],
               end_date: ~D[2026-07-31],
               active: true
             })

    assert year.active
    assert Organization.current_academic_year(ws).id == year.id
  end

  test "creating a second active year deactivates the first", %{ws: ws} do
    {:ok, y1} =
      Organization.create_academic_year(ws, %{
        name: "2024-2025",
        start_date: ~D[2024-09-01],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, _y2} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, y1_reloaded} = Organization.get_academic_year(y1.id, ws)
    refute y1_reloaded.active
  end
end
