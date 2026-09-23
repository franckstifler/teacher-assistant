defmodule TeacherAssistant.Academics.ClassGroupTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{ws: ws, year: year}
  end

  test "creates a class group scoped to workspace + year", %{ws: ws, year: year} do
    {:ok, cg} =
      Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème", serie: nil})

    assert cg.label == "3e M2"
    assert cg.subsystem == :francophone
    assert cg.workspace_id == ws.id
    assert cg.academic_year_id == year.id
  end

  test "lists class groups for the year", %{ws: ws, year: year} do
    {:ok, _} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    assert [%{label: "3e M2"}] = Enrollment.list_class_groups(ws, year)
  end

  test "fetch_owned_class_group refuses another workspace's group", %{ws: ws, year: year} do
    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{workspace: other} = TeacherFixtures.school_fixture()
    assert {:error, :not_found} = Enrollment.fetch_owned_class_group(cg.id, other)
    assert {:ok, %{id: id}} = Enrollment.fetch_owned_class_group(cg.id, ws)
    assert id == cg.id
  end
end
