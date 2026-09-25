defmodule TeacherAssistant.Academics.EnrollmentsTest do
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
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    %{ws: ws, scope: scope, year: year, cg: cg, cg2: cg2}
  end

  test "enroll_new creates student + inscription enrollment", %{cg: cg, scope: scope} do
    {:ok, %{student: s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert e.status == :inscription and e.student_id == s.id
  end

  test "enroll_new rejects duplicate matricule", %{cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert {:error, :duplicate_matricule} =
             Enrollment.enroll_new(scope, cg, %{full_name: "Bi", sex: :m, matricule: "M-1"})
  end

  test "enroll_existing re-enrolls as réinscription; double-enroll rejected", ctx do
    %{cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, %{student: s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    :ok = Enrollment.withdraw(scope, e)
    {:ok, e2} = Enrollment.enroll_existing(scope, cg2, s)
    assert e2.status == :reinscription and e2.class_group_id == cg2.id
    assert {:error, :already_enrolled} = Enrollment.enroll_existing(scope, cg, s)
  end

  test "enroll_new rolls back the Student when the Enrollment insert fails", %{
    cg: cg,
    scope: scope
  } do
    stale_cg = %{cg | academic_year_id: Ash.UUID.generate()}

    assert {:error, reason} =
             Enrollment.enroll_new(scope, stale_cg, %{
               full_name: "Orphan Candidate",
               sex: :f,
               matricule: "M-ORPHAN"
             })

    refute reason == :duplicate_matricule

    assert Enrollment.search_students(scope, "Orphan Candidate") == []
    assert Enrollment.search_students(scope, "M-ORPHAN") == []
  end

  test "enroll_existing does not mislabel a stale class_group FK violation as already_enrolled",
       %{cg: cg, scope: scope} do
    {:ok, %{student: s}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    stale_cg = %{cg | academic_year_id: Ash.UUID.generate()}

    assert {:error, reason} = Enrollment.enroll_existing(scope, stale_cg, s)
    refute reason == :already_enrolled
  end

  test "search_students finds by matricule and by name fragment", %{cg: cg, scope: scope} do
    {:ok, _} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Ngo Bassa Marie", sex: :f, matricule: "M-9"})

    assert [%{matricule: "M-9"}] = Enrollment.search_students(scope, "M-9")
    assert [%{full_name: "Ngo Bassa Marie"}] = Enrollment.search_students(scope, "bassa")
    assert [] = Enrollment.search_students(scope, "zzz")
  end

  test "transfer moves the enrollment to another class in the same year", ctx do
    %{cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, e} = Enrollment.transfer(scope, e, cg2)
    assert e.class_group_id == cg2.id
  end

  test "transfer to a different year is rejected", %{ws: ws, cg: cg, scope: scope} do
    {:ok, other_year} =
      Organization.create_academic_year(ws, %{
        name: "2026-2027",
        start_date: ~D[2026-09-07],
        end_date: ~D[2027-07-31],
        active: false
      })

    {:ok, cg_other} =
      Enrollment.create_class_group(scope, other_year, %{label: "5e A", level: "5ème"})

    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    assert {:error, :different_year} = Enrollment.transfer(scope, e, cg_other)
  end

  test "import_rows: creates, re-enrolls by matricule, flags same-year conflicts", ctx do
    %{cg: cg, cg2: cg2, scope: scope} = ctx
    # existing student with matricule, not enrolled this year in cg2's class
    {:ok, %{student: _s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollment.withdraw(scope, e)
    # still-enrolled student → conflict
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    rows = [
      %{full_name: "Awa", sex: :f, matricule: "M-1", repeater: false},
      %{full_name: "Bi", sex: :m, matricule: "M-2", repeater: false},
      %{full_name: "Cam", sex: :m, matricule: nil, repeater: true}
    ]

    result = Enrollment.import_rows(scope, cg2, rows)
    assert result.created == 1
    assert result.reenrolled == 1
    assert [%{matricule: "M-2", reason: :already_enrolled}] = result.conflicts
  end
end
