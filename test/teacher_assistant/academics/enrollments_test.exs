defmodule TeacherAssistant.Academics.EnrollmentsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
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
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})
    %{ws: ws, year: year, cg: cg, cg2: cg2}
  end

  test "enroll_new creates student + inscription enrollment", %{cg: cg} do
    {:ok, %{student: s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert e.status == :inscription and e.student_id == s.id
  end

  test "enroll_new rejects duplicate matricule", %{cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert {:error, :duplicate_matricule} =
             Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-1"})
  end

  test "enroll_existing re-enrolls as réinscription; double-enroll rejected", ctx do
    %{cg: cg, cg2: cg2} = ctx
    {:ok, %{student: s, enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    :ok = Enrollments.withdraw(e)
    {:ok, e2} = Enrollments.enroll_existing(cg2, s)
    assert e2.status == :reinscription and e2.class_group_id == cg2.id
    assert {:error, :already_enrolled} = Enrollments.enroll_existing(cg, s)
  end

  test "search_students finds by matricule and by name fragment", %{ws: ws, cg: cg} do
    {:ok, _} =
      Enrollments.enroll_new(cg, %{full_name: "Ngo Bassa Marie", sex: :f, matricule: "M-9"})

    assert [%{matricule: "M-9"}] = Enrollments.search_students(ws, "M-9")
    assert [%{full_name: "Ngo Bassa Marie"}] = Enrollments.search_students(ws, "bassa")
    assert [] = Enrollments.search_students(ws, "zzz")
  end

  test "transfer moves the enrollment to another class in the same year", ctx do
    %{cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, e} = Enrollments.transfer(e, cg2)
    assert e.class_group_id == cg2.id
  end

  test "transfer to a different year is rejected", %{ws: ws, cg: cg} do
    {:ok, other_year} =
      Academics.create_academic_year(ws, %{
        name: "2026-2027",
        start_date: ~D[2026-09-07],
        end_date: ~D[2027-07-31],
        active: false
      })

    {:ok, cg_other} =
      Academics.create_class_group(ws, other_year, %{label: "5e A", level: "5ème"})

    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    assert {:error, :different_year} = Enrollments.transfer(e, cg_other)
  end

  test "import_rows: creates, re-enrolls by matricule, flags same-year conflicts", ctx do
    %{cg: cg, cg2: cg2} = ctx
    # existing student with matricule, not enrolled this year in cg2's class
    {:ok, %{student: _s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)
    # still-enrolled student → conflict
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    rows = [
      %{full_name: "Awa", sex: :f, matricule: "M-1", repeater: false},
      %{full_name: "Bi", sex: :m, matricule: "M-2", repeater: false},
      %{full_name: "Cam", sex: :m, matricule: nil, repeater: true}
    ]

    result = Enrollments.import_rows(cg2, rows)
    assert result.created == 1
    assert result.reenrolled == 1
    assert [%{matricule: "M-2", reason: :already_enrolled}] = result.conflicts
  end
end
