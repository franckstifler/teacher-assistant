defmodule TeacherAssistant.Academics.StudentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, scope: scope, cg: cg}
  end

  test "adds a student with required sex", %{cg: cg, ws: ws, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa Bello", sex: :f})
    assert s.full_name == "Awa Bello"
    assert s.sex == :f
    assert s.workspace_id == ws.id
  end

  test "lists students alphabetically", %{cg: cg, scope: scope} do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Zoa", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    assert ["Awa", "Zoa"] = Enrollment.list_students(scope, cg) |> Enum.map(& &1.full_name)
  end

  test "sex is required", %{cg: cg, scope: scope} do
    assert {:error, _} = Enrollment.add_student(scope, cg, %{full_name: "No Sex"})
  end

  test "fetch_owned_student refuses another workspace", %{cg: cg, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    %{scope: other_scope} = TeacherFixtures.school_fixture()
    assert {:error, :not_found} = Enrollment.fetch_owned_student(other_scope, s.id)
    assert {:ok, %{id: id}} = Enrollment.fetch_owned_student(scope, s.id)
    assert id == s.id
  end

  test "does not leave an orphaned student when enrollment fails", %{cg: cg, scope: scope, ws: ws} do
    bogus_cg = %{cg | id: Ecto.UUID.generate()}

    assert {:error, _} = Enrollment.add_student(scope, bogus_cg, %{full_name: "Orphan", sex: :f})

    require Ash.Query

    students =
      TeacherAssistant.Academics.Student
      |> Ash.Query.filter(full_name == "Orphan")
      |> Ash.Query.set_tenant(ws.id)
      |> Ash.read!(authorize?: false)

    assert students == []
  end
end
