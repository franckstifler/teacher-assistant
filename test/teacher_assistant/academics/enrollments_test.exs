defmodule TeacherAssistant.Academics.EnrollmentsTest do
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

    :ok = Enrollment.remove_mistaken(scope, e)
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

  test "transfer to a different year is rejected", %{cg: cg, scope: scope} do
    {:ok, other_year} =
      Organization.create_academic_year(scope, %{
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

  test "import_rows: creates, re-enrolls by matricule, skips same-year conflicts", ctx do
    %{cg: cg, cg2: cg2, scope: scope} = ctx
    # existing student with matricule, not enrolled this year in cg2's class
    {:ok, %{student: _s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollment.remove_mistaken(scope, e)
    # still-enrolled student → conflict
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    rows = [
      %{full_name: "Awa", sex: :f, matricule: "M-1", repeater: false, guardian: nil},
      %{full_name: "Bi", sex: :m, matricule: "M-2", repeater: false, guardian: nil},
      %{full_name: "Cam", sex: :m, matricule: nil, repeater: true, guardian: nil},
      %{full_name: "Dodo", sex: nil, matricule: nil, repeater: false, guardian: nil}
    ]

    result = Enrollment.import_rows(scope, cg2, rows)
    assert result.created == 1
    assert result.reenrolled == 1

    assert [%{full_name: "Bi", reason: :already_enrolled}, %{full_name: "Dodo", reason: :sex}] =
             result.skipped
  end

  describe "preview_rows/3" do
    setup %{scope: scope, cg: cg} do
      {:ok, old_year} =
        Organization.create_academic_year(scope, %{
          name: "2024-2025",
          start_date: ~D[2024-09-09],
          end_date: ~D[2025-07-31],
          active: false
        })

      {:ok, old_cg} =
        Enrollment.create_class_group(scope, old_year, %{label: "5e C", level: "5ème"})

      {:ok, %{student: former}} =
        Enrollment.enroll_new(scope, old_cg, %{
          full_name: "Ébogo Sandrine",
          sex: :f,
          matricule: "M-7"
        })

      {:ok, %{student: current}} =
        Enrollment.enroll_new(scope, cg, %{full_name: "Nana Eric", sex: :m, matricule: "M-8"})

      {:ok, rose} =
        Enrollment.add_guardian(scope, current, %{
          full_name: "Bekono Rose",
          relationship: :mere,
          phone: "699 10 22 33"
        })

      %{former: former, rose: rose}
    end

    defp actions(scope, cg, raw) do
      scope
      |> Enrollment.preview_rows(cg, TeacherAssistant.Academics.RosterLine.parse(raw))
      |> Enum.map(fn {row, action, parent} -> {row.full_name, action, parent} end)
    end

    test "classifies each row and its parent", %{scope: scope, cg2: cg2} = ctx do
      %{former: former, rose: rose} = ctx

      assert [
               {"Abessolo Marc", :create, {:new, "677 45 12 90"}},
               {"Bekono Aline", :create, {:existing, guardian}},
               {"sandrine EBOGO", {:reenroll, reenrolled, last}, nil},
               {"Nana Eric", {:conflict, :already_enrolled, "6e A"}, nil},
               {"Kana Brice", {:error, :sex}, {:invalid, "690 22"}}
             ] =
               actions(scope, cg2, """
               Abessolo Marc;M;;12/02/2014;677 45 12 90
               Bekono Aline;F;;;+237 699 10 22 33
               sandrine EBOGO;F;M-7
               Nana Eric;G;M-8
               Kana Brice;;;;690 22
               """)

      assert [{"Mvogo Diane", {:conflict, :matricule_taken, "Ébogo Sandrine"}, nil}] =
               actions(scope, cg2, "Mvogo Diane;F;M-7")

      assert guardian.id == rose.id
      assert reenrolled.id == former.id
      assert last.class_group.label == "5e C"
      assert last.academic_year.name == "2024-2025"
    end

    test "a matricule repeated in the paste: only its first line counts", %{
      scope: scope,
      cg2: cg2
    } do
      assert [
               {"Owono Steve", :create, nil},
               {"Owono Léa", {:conflict, :repeated_in_list, "Owono Steve"}, nil}
             ] = actions(scope, cg2, "Owono Steve;M;M-50\nOwono Léa;F;M-50")
    end

    test "an invalid parent number is reported, not attempted", %{scope: scope, cg2: cg2} do
      result =
        Enrollment.import_rows(
          scope,
          cg2,
          TeacherAssistant.Academics.RosterLine.parse("Kana Brice;M;;;690 22")
        )

      assert result.created == 1
      assert [%{full_name: "Kana Brice", phone: "690 22"}] = result.guardian_issues
    end

    test "two siblings with one new number share one parent", %{scope: scope, cg2: cg2} do
      Enrollment.import_rows(
        scope,
        cg2,
        TeacherAssistant.Academics.RosterLine.parse(
          "Owono Steve;M;;;6 95 12 12 12\nOwono Léa;F;;;695121212"
        )
      )

      [steve, lea] =
        scope |> Enrollment.list_students(cg2) |> Enum.sort_by(& &1.full_name, :desc)

      [%{guardian_id: g1}] = Enrollment.list_guardian_links(scope, steve)
      [%{guardian_id: g2}] = Enrollment.list_guardian_links(scope, lea)
      assert g1 == g2
    end
  end
end
