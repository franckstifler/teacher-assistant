defmodule TeacherAssistant.Academics.CoursesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg_maco} =
      Enrollment.create_class_group(scope, year, %{label: "1ère A MACO", level: "1ère"})

    {:ok, cg_menu} =
      Enrollment.create_class_group(scope, year, %{label: "1ère A MENU", level: "1ère"})

    {:ok, tc_maco} = Curriculum.assign_teacher(scope, cg_maco, head, %{subject: "Mathématiques"})
    {:ok, tc_menu} = Curriculum.assign_teacher(scope, cg_menu, head, %{subject: "Mathématiques"})
    {:ok, tc_french} = Curriculum.assign_teacher(scope, cg_maco, head, %{subject: "Français"})

    %{
      head: head,
      ws: ws,
      scope: scope,
      year: year,
      cg_maco: cg_maco,
      cg_menu: cg_menu,
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      tc_french: tc_french
    }
  end

  test "combine links contexts and creates one shared plan", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, scope: scope} = ctx

    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    assert Enum.sort([tc_maco.id, tc_menu.id]) ==
             Enum.sort(Enum.map(Curriculum.contexts_of_course!(course.id, scope: scope), & &1.id))

    assert [_plan] =
             Curriculum.list_progression_plans!(scope: scope)
             |> Enum.filter(&(&1.combined_course_id == course.id))
  end

  test "combine builds the label from real class labels, not the bare level", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, scope: scope} = ctx
    # tc_maco/tc_menu come straight from Curriculum.assign_teacher/4 — neither has
    # :class_group preloaded. combine/2 must load it itself, otherwise both
    # contexts (same level "1ère") collapse to a single bare-level label.
    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    assert course.label == "Mathématiques · 1ère A MACO+1ère A MENU"
  end

  test "combine rejects mismatched subject/teacher and <2", ctx do
    %{tc_maco: tc_maco, tc_french: tc_french, cg_menu: cg_menu, scope: scope} = ctx

    assert {:error, :need_two} = Curriculum.combine_course(scope, [tc_maco])
    assert {:error, :subject_mismatch} = Curriculum.combine_course(scope, [tc_maco, tc_french])

    other = TeacherFixtures.user_fixture()
    {:ok, _} = add_active_member(ctx.ws, ctx.head, other)
    {:ok, tc_other} = Curriculum.assign_teacher(scope, cg_menu, other, %{subject: "Français"})

    assert {:error, :teacher_mismatch} = Curriculum.combine_course(scope, [tc_french, tc_other])
  end

  test "combine rejects a context already in a course", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, cg_maco: cg_maco, head: head, scope: scope} = ctx

    {:ok, _course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    {:ok, cg_third} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "1ère B", level: "1ère"})

    {:ok, tc_third} =
      Curriculum.assign_teacher(scope, cg_third, head, %{subject: "Mathématiques"})

    tc_maco = Curriculum.get_teaching_context(scope, tc_maco.id) |> elem(1)

    assert {:error, :already_combined} = Curriculum.combine_course(scope, [tc_maco, tc_third])
    refute cg_maco == nil
  end

  describe "split" do
    setup ctx do
      {:ok, course} = Curriculum.combine_course(ctx.scope, [ctx.tc_maco, ctx.tc_menu])
      %{course: course}
    end

    test "split unlinks contexts and removes the course and its plan", ctx do
      %{course: course, tc_maco: tc_maco, tc_menu: tc_menu, scope: scope} = ctx

      assert :ok = Curriculum.split_course(scope, course)

      assert Curriculum.get_teaching_context(scope, tc_maco.id)
             |> elem(1)
             |> Map.get(:combined_course_id) ==
               nil

      assert Curriculum.get_teaching_context(scope, tc_menu.id)
             |> elem(1)
             |> Map.get(:combined_course_id) ==
               nil

      assert {:error, _} = Curriculum.get_course(scope, course.id)

      assert [] =
               Curriculum.list_progression_plans!(scope: scope)
               |> Enum.filter(&(&1.combined_course_id == course.id))
    end
  end

  test "list_units collapses combined contexts into one entry", ctx do
    %{
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      tc_french: tc_french,
      year: year,
      head: head,
      scope: scope
    } =
      ctx

    {:ok, _} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    units = Curriculum.list_units_for_user(scope, year, head)

    assert Enum.count(units, &match?({:course, _}, &1)) == 1
    assert Enum.count(units, &match?({:solo, _}, &1)) == 1

    assert {:course, course_unit} = Enum.find(units, &match?({:course, _}, &1))
    assert course_unit.subject == "Mathématiques"

    assert {:solo, solo_ctx} = Enum.find(units, &match?({:solo, _}, &1))
    assert solo_ctx.id == tc_french.id
  end

  test "unit_plans hides stale member-context plans after combining", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, tc_french: tc_french, scope: scope} = ctx

    {:ok, _stale_maco_plan} =
      Curriculum.create_progression_plan(scope, tc_maco, %{title: "Maco (stale)"})

    {:ok, _stale_menu_plan} =
      Curriculum.create_progression_plan(scope, tc_menu, %{title: "Menu (stale)"})

    {:ok, french_plan} =
      Curriculum.create_progression_plan(scope, tc_french, %{title: "Français"})

    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    unit_plans = Curriculum.unit_plans!(scope: scope)

    assert length(unit_plans) == 2
    assert Enum.count(unit_plans, &(&1.combined_course_id == course.id)) == 1
    assert Enum.any?(unit_plans, &(&1.id == french_plan.id))
    refute Enum.any?(unit_plans, &(&1.teaching_context_id in [tc_maco.id, tc_menu.id]))
  end

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(user.email),
        roles: [:teacher]
      })

    Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: user}, inv.token)
  end
end
