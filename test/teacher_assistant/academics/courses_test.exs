defmodule TeacherAssistant.Academics.CoursesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Courses}
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg_maco} =
      Academics.create_class_group(ws, year, %{label: "1ère A MACO", level: "1ère"})

    {:ok, cg_menu} =
      Academics.create_class_group(ws, year, %{label: "1ère A MENU", level: "1ère"})

    {:ok, tc_maco} = Assignments.assign(cg_maco, head, %{subject: "Mathématiques"})
    {:ok, tc_menu} = Assignments.assign(cg_menu, head, %{subject: "Mathématiques"})
    {:ok, tc_french} = Assignments.assign(cg_maco, head, %{subject: "Français"})

    %{
      head: head,
      ws: ws,
      year: year,
      cg_maco: cg_maco,
      cg_menu: cg_menu,
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      tc_french: tc_french
    }
  end

  test "combine links contexts and creates one shared plan", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, ws: ws} = ctx

    {:ok, course} = Courses.combine([tc_maco, tc_menu])

    assert Enum.sort([tc_maco.id, tc_menu.id]) ==
             Enum.sort(Enum.map(Academics.contexts_of_course(course), & &1.id))

    assert [_plan] =
             Academics.list_progression_plans(ws)
             |> Enum.filter(&(&1.combined_course_id == course.id))
  end

  test "combine rejects mismatched subject/teacher and <2", ctx do
    %{tc_maco: tc_maco, tc_french: tc_french, cg_menu: cg_menu} = ctx

    assert {:error, :need_two} = Courses.combine([tc_maco])
    assert {:error, :subject_mismatch} = Courses.combine([tc_maco, tc_french])

    other = TeacherFixtures.user_fixture()
    {:ok, _} = add_active_member(ctx.ws, ctx.head, other)
    {:ok, tc_other} = Assignments.assign(cg_menu, other, %{subject: "Français"})

    assert {:error, :teacher_mismatch} = Courses.combine([tc_french, tc_other])
  end

  test "combine rejects a context already in a course", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, cg_maco: cg_maco, head: head} = ctx

    {:ok, _course} = Courses.combine([tc_maco, tc_menu])

    {:ok, cg_third} =
      Academics.create_class_group(ctx.ws, ctx.year, %{label: "1ère B", level: "1ère"})

    {:ok, tc_third} = Assignments.assign(cg_third, head, %{subject: "Mathématiques"})
    tc_maco = Academics.get_teaching_context(tc_maco.id) |> elem(1)

    assert {:error, :already_combined} = Courses.combine([tc_maco, tc_third])
    refute cg_maco == nil
  end

  describe "split" do
    setup ctx do
      {:ok, course} = Courses.combine([ctx.tc_maco, ctx.tc_menu])
      %{course: course}
    end

    test "split unlinks contexts and removes the course and its plan", ctx do
      %{course: course, tc_maco: tc_maco, tc_menu: tc_menu, ws: ws} = ctx

      assert :ok = Courses.split(course)

      assert Academics.get_teaching_context(tc_maco.id) |> elem(1) |> Map.get(:combined_course_id) ==
               nil

      assert Academics.get_teaching_context(tc_menu.id) |> elem(1) |> Map.get(:combined_course_id) ==
               nil

      assert {:error, _} = Academics.get_course(course.id)

      assert [] =
               Academics.list_progression_plans(ws)
               |> Enum.filter(&(&1.combined_course_id == course.id))
    end
  end

  test "list_units collapses combined contexts into one entry", ctx do
    %{tc_maco: tc_maco, tc_menu: tc_menu, tc_french: tc_french, ws: ws, year: year, head: head} =
      ctx

    {:ok, _} = Courses.combine([tc_maco, tc_menu])

    units = Courses.list_units_for_user(ws, year, head)

    assert Enum.count(units, &match?({:course, _}, &1)) == 1
    assert Enum.count(units, &match?({:solo, _}, &1)) == 1

    assert {:course, course_unit} = Enum.find(units, &match?({:course, _}, &1))
    assert course_unit.subject == "Mathématiques"

    assert {:solo, solo_ctx} = Enum.find(units, &match?({:solo, _}, &1))
    assert solo_ctx.id == tc_french.id
  end

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    Schools.accept_invitation(inv.token, user)
  end
end
