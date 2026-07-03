defmodule TeacherAssistant.Academics.EnrollmentsModelTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    %{ws: ws, year: year, cg: cg}
  end

  test "add_student creates a student and an enrollment", %{ws: ws, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f, repeater: true})
    assert s.workspace_id == ws.id
    assert [%{student: student, enrollment: enr}] = Academics.list_roster(cg)
    assert student.id == s.id
    assert enr.class_group_id == cg.id
    assert enr.repeater == true
    assert enr.status == :inscription
  end

  test "list_students returns enrolled students sorted by name", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Zoe", sex: :f})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Ali", sex: :m})
    assert ["Ali", "Zoe"] = Academics.list_students(cg) |> Enum.map(& &1.full_name)
  end

  test "matricule is unique per workspace", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f, matricule: "MAT-1"})

    assert {:error, _} =
             Academics.add_student(cg, %{full_name: "Bi", sex: :m, matricule: "MAT-1"})

    # nil matricules never collide
    {:ok, _} = Academics.add_student(cg, %{full_name: "Cam", sex: :m})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Dan", sex: :m})
  end

  test "a student has one enrollment per year", %{ws: ws, year: year, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    assert {:error, _} =
             TeacherAssistant.Academics.Enrollment
             |> Ash.Changeset.for_create(:create, %{
               student_id: s.id,
               class_group_id: cg2.id,
               academic_year_id: year.id,
               workspace_id: ws.id
             })
             |> Ash.create(authorize?: false)
  end

  test "update_enrollment toggles repeater", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enr}] = Academics.list_roster(cg)
    {:ok, enr} = Academics.update_enrollment(enr, %{repeater: true})
    assert enr.repeater
  end

  test "delete_student cascades its enrollments", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    :ok = Academics.delete_student(s)
    assert Academics.list_roster(cg) == []
  end

  test "fetch_owned_student scopes by workspace", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    other = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())
    assert {:ok, _} = Academics.fetch_owned_student(s.id, %{other | id: s.workspace_id})
    assert {:error, :not_found} = Academics.fetch_owned_student(s.id, other)
  end
end
