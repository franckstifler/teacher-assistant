defmodule TeacherAssistant.DisciplineSchoolSanctionsTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Discipline, Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg_a, cg_b | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg_a, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg_b, %{full_name: "Bob", sex: :m})
    [%{enrollment: awa}] = Enrollment.list_roster(scope, cg_a)
    [%{enrollment: bob}] = Enrollment.list_roster(scope, cg_b)
    %{scope: scope, year: year, cg_a: cg_a, awa: awa, bob: bob}
  end

  test "the school list filters by class, type and parents to notify, newest first", ctx do
    {:ok, s1} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: ~D[2025-09-10]})
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :blame, date: ~D[2025-09-12]})
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.bob, %{type: :consigne, date: ~D[2025-09-11]})
    {:ok, _} = Discipline.mark_parents_notified(ctx.scope, s1)

    page = Discipline.list_school_sanctions(ctx.scope, ctx.year, [])
    assert page.count == 3
    assert Enum.map(page.results, & &1.type) == [:blame, :consigne, :avertissement]
    assert hd(page.results).enrollment.student.full_name == "Awa"

    assert [%{type: :consigne}] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year, type: :consigne).results

    assert [_, _] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year, class_group_id: ctx.cg_a.id).results

    assert [%{type: :blame}] =
             Discipline.list_school_sanctions(ctx.scope, ctx.year,
               class_group_id: ctx.cg_a.id,
               to_notify: true
             ).results

    assert Discipline.count_parents_to_notify(ctx.scope, ctx.year) == 2
  end

  test "a type switched off is refused wherever the sanction comes from", ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{sanction_types_in_use: [:avertissement]},
        scope: ctx.scope
      )
      |> Ash.update()

    assert {:error, :type_not_in_use} =
             Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :blame, date: ~D[2025-09-10]})

    assert Discipline.list_school_sanctions(ctx.scope, ctx.year, []).count == 0
    assert {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: ~D[2025-09-10]})
  end
end
