defmodule TeacherAssistant.Academics.EnrollmentsModelTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    %{ws: ws, scope: scope, year: year, cg: cg}
  end

  test "add_student creates a student and an enrollment", %{ws: ws, cg: cg, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f, repeater: true})
    assert s.workspace_id == ws.id
    assert [%{student: student, enrollment: enr}] = Enrollment.list_roster(scope, cg)
    assert student.id == s.id
    assert enr.class_group_id == cg.id
    assert enr.repeater == true
    assert enr.status == :inscription
  end

  test "list_students returns enrolled students sorted by name", %{cg: cg, scope: scope} do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Zoe", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Ali", sex: :m})
    assert ["Ali", "Zoe"] = Enrollment.list_students(scope, cg) |> Enum.map(& &1.full_name)
  end

  test "matricule is unique per workspace", %{cg: cg, scope: scope} do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f, matricule: "MAT-1"})

    assert {:error, _} =
             Enrollment.add_student(scope, cg, %{full_name: "Bi", sex: :m, matricule: "MAT-1"})

    # nil matricules never collide
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Cam", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Dan", sex: :m})
  end

  test "a student has one enrollment per year", %{ws: ws, year: year, cg: cg, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    assert {:error, _} =
             TeacherAssistant.Academics.Enrollment
             |> Ash.Changeset.for_create(:create, %{
               student_id: s.id,
               class_group_id: cg2.id,
               academic_year_id: year.id
             })
             |> Ash.Changeset.set_tenant(ws.id)
             |> Ash.create(authorize?: false)
  end

  test "update_enrollment toggles repeater", %{cg: cg, scope: scope} do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enr}] = Enrollment.list_roster(scope, cg)
    {:ok, enr} = Enrollment.update_enrollment(enr, %{repeater: true}, scope: scope)
    assert enr.repeater
  end

  test "delete_student cascades its enrollments", %{cg: cg, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    :ok = Enrollment.delete_student(scope, s)
    assert Enrollment.list_roster(scope, cg) == []
  end

  test "fetch_owned_student scopes by workspace", %{cg: cg, scope: scope} do
    {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    %{scope: other_scope} = TeacherFixtures.school_fixture()
    assert {:ok, _} = Enrollment.fetch_owned_student(scope, s.id)
    assert {:error, :not_found} = Enrollment.fetch_owned_student(other_scope, s.id)
  end
end
