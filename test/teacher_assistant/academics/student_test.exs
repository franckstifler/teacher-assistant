defmodule TeacherAssistant.Academics.StudentTest do
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

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, cg: cg}
  end

  test "adds a student with required sex", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa Bello", sex: :f})
    assert s.full_name == "Awa Bello"
    assert s.sex == :f
    assert s.repeater == false
    assert s.class_group_id == cg.id
  end

  test "lists students alphabetically", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Zoa", sex: :m})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    assert ["Awa", "Zoa"] = Academics.list_students(cg) |> Enum.map(& &1.full_name)
  end

  test "sex is required", %{cg: cg} do
    assert {:error, _} = Academics.add_student(cg, %{full_name: "No Sex"})
  end

  test "fetch_owned_student refuses another workspace", %{ws: ws, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.fetch_owned_student(s.id, other)
    assert {:ok, %{id: id}} = Academics.fetch_owned_student(s.id, ws)
    assert id == s.id
  end
end
