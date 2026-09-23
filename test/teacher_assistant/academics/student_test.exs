defmodule TeacherAssistant.Academics.StudentTest do
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

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, cg: cg}
  end

  test "adds a student with required sex", %{cg: cg, ws: ws} do
    {:ok, s} = Enrollment.add_student(cg, %{full_name: "Awa Bello", sex: :f})
    assert s.full_name == "Awa Bello"
    assert s.sex == :f
    assert s.workspace_id == ws.id
  end

  test "lists students alphabetically", %{cg: cg} do
    {:ok, _} = Enrollment.add_student(cg, %{full_name: "Zoa", sex: :m})
    {:ok, _} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    assert ["Awa", "Zoa"] = Enrollment.list_students(cg) |> Enum.map(& &1.full_name)
  end

  test "sex is required", %{cg: cg} do
    assert {:error, _} = Enrollment.add_student(cg, %{full_name: "No Sex"})
  end

  test "fetch_owned_student refuses another workspace", %{ws: ws, cg: cg} do
    {:ok, s} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    %{workspace: other} = TeacherFixtures.school_fixture()
    assert {:error, :not_found} = Enrollment.fetch_owned_student(s.id, other)
    assert {:ok, %{id: id}} = Enrollment.fetch_owned_student(s.id, ws)
    assert id == s.id
  end

  test "does not leave an orphaned student when enrollment fails", %{cg: cg, ws: ws} do
    bogus_cg = %{cg | id: Ecto.UUID.generate()}

    assert {:error, _} = Enrollment.add_student(bogus_cg, %{full_name: "Orphan", sex: :f})

    require Ash.Query

    students =
      TeacherAssistant.Academics.Student
      |> Ash.Query.filter(workspace_id == ^ws.id and full_name == "Orphan")
      |> Ash.read!(authorize?: false)

    assert students == []
  end
end
