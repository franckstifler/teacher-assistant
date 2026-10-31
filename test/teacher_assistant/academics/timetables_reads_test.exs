defmodule TeacherAssistant.Academics.TimetablesReadsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture(%{name: "Jean Abena"})

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, tc_maths} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", weekly_hours: 5})

    {:ok, tc_eps} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "EPS", weekly_hours: 2})

    {:ok, tc_svt} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "SVT", weekly_hours: 3})

    :ok = Attendance.build_default_periods(scope)

    periods =
      Attendance.list_periods(scope)
      |> Enum.filter(&(&1.kind == :lesson))

    %{
      head: head,
      scope: scope,
      school: school,
      year: year,
      cg: cg,
      tc_maths: tc_maths,
      tc_eps: tc_eps,
      tc_svt: tc_svt,
      periods: periods
    }
  end

  describe "class_timetable/2" do
    test "returns keyed slots and a tally row per assignment", ctx do
      %{
        cg: cg,
        tc_maths: tc_maths,
        tc_eps: tc_eps,
        tc_svt: tc_svt,
        periods: periods,
        scope: scope
      } =
        ctx

      [p1, p2, p3 | _] = periods

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :tuesday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :wednesday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p2.id,
          teaching_context_id: tc_eps.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc_eps.id
        })

      result = Timetabling.class_timetable(scope, cg)

      assert map_size(result.slots) == 5

      slot_view = Map.fetch!(result.slots, {:monday, p1.id})
      assert slot_view.teaching_context_id == tc_maths.id
      assert slot_view.subject == "Maths"
      assert slot_view.teacher_name == "Jean Abena"
      assert slot_view.day == :monday
      assert slot_view.period_id == p1.id

      tally_by_tc = Map.new(result.tally, &{&1.teaching_context_id, &1})

      maths_row = Map.fetch!(tally_by_tc, tc_maths.id)
      assert maths_row.subject == "Maths"
      assert maths_row.placed == 3
      assert maths_row.required == 5
      assert maths_row.status == :under

      eps_row = Map.fetch!(tally_by_tc, tc_eps.id)
      assert eps_row.subject == "EPS"
      assert eps_row.placed == 2
      assert eps_row.required == 2
      assert eps_row.status == :exact

      svt_row = Map.fetch!(tally_by_tc, tc_svt.id)
      assert svt_row.subject == "SVT"
      assert svt_row.placed == 0
      assert svt_row.required == 3
      assert svt_row.status == :under

      assert length(result.tally) == 3

      refute is_nil(p3)
    end
  end

  describe "teacher_timetable/2" do
    test "includes cells from all classes the teacher teaches in, with class_label", ctx do
      %{
        head: head,
        year: year,
        cg: cg_a,
        tc_maths: tc_maths,
        periods: periods,
        scope: scope
      } =
        ctx

      [p1, p2 | _] = periods

      {:ok, cg_b} =
        Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

      {:ok, tc_b} =
        Curriculum.assign_teacher(scope, cg_b, head, %{subject: "Histoire", weekly_hours: 3})

      {:ok, _} =
        Timetabling.place_slot(scope, cg_a, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg_b, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc_b.id
        })

      result = Timetabling.teacher_timetable(%{scope | current_academic_year: year}, head)

      assert map_size(result) == 2

      [cell_a] = Map.fetch!(result, {:monday, p1.id})
      assert cell_a.teaching_context_id == tc_maths.id
      assert cell_a.class_label == "6e A"
      assert cell_a.subject == "Maths"

      [cell_b] = Map.fetch!(result, {:tuesday, p2.id})
      assert cell_b.teaching_context_id == tc_b.id
      assert cell_b.class_label == "6e B"
      assert cell_b.subject == "Histoire"
    end

    test "only the scope's current year", ctx do
      %{head: head, cg: cg, tc_maths: tc_maths, periods: [p1, p2 | _], scope: scope, year: year} =
        ctx

      {:ok, old_year} =
        Organization.create_academic_year(scope, %{
          name: "2024-2025",
          start_date: ~D[2024-09-09],
          end_date: ~D[2025-07-31],
          active: false
        })

      {:ok, old_cg} =
        Enrollment.create_class_group(scope, old_year, %{label: "6e A", level: "6ème"})

      {:ok, old_tc} = Curriculum.assign_teacher(scope, old_cg, head, %{subject: "Physique"})

      {:ok, _} =
        Timetabling.place_slot(scope, old_cg, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: old_tc.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc_maths.id
        })

      current = %{scope | current_academic_year: year}
      assert Map.keys(Timetabling.teacher_timetable(current, head)) == [{:tuesday, p2.id}]

      assert Timetabling.teacher_timetable(%{scope | current_academic_year: nil}, head) == %{}
    end

    test "returns an empty map for a teacher with no slots", ctx do
      other_teacher = TeacherFixtures.user_fixture()

      assert Timetabling.teacher_timetable(ctx.scope, other_teacher) == %{}
    end
  end

  describe "all_teacher_timetables/1" do
    test "lists teachers with lessons, by name", ctx do
      %{scope: scope, year: year, cg: cg, tc_maths: tc_maths, periods: [p1, p2 | _]} = ctx
      scope = %{scope | current_academic_year: year}

      alain = TeacherFixtures.user_fixture(%{name: "Alain Mbarga"})

      %{teaching_context: tc_alain} =
        TeacherFixtures.school_teacher_fixture(scope, %{
          teacher: alain,
          class_group: cg,
          subject: "Anglais"
        })

      _idle = TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "ESF"})

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p2.id,
          teaching_context_id: tc_alain.id
        })

      result = Timetabling.all_teacher_timetables(scope)

      assert Enum.map(result, & &1.teacher.name) == ["Alain Mbarga", "Jean Abena"]
      [alain_sheet, _jean] = result
      assert [%{class_label: "6e A", subject: "Anglais"}] = alain_sheet.grid[{:monday, p2.id}]
    end

    test "a combined course shows both classes in the teacher's cell", ctx do
      %{scope: scope, year: year, head: head, tc_maths: tc_maths, periods: [p1 | _]} = ctx
      scope = %{scope | current_academic_year: year}

      {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
      {:ok, tc_b} = Curriculum.assign_teacher(scope, cg_b, head, %{subject: "Maths"})
      {:ok, course} = Curriculum.combine_course(scope, [tc_maths, tc_b])
      {:ok, _} = Timetabling.place_combined_slot(scope, course, :monday, p1.id)

      [%{grid: grid}] = Timetabling.all_teacher_timetables(scope)
      assert Enum.map(grid[{:monday, p1.id}], & &1.class_label) == ["6e A", "6e B"]
    end

    test "is empty without a current year", ctx do
      assert Timetabling.all_teacher_timetables(%{ctx.scope | current_academic_year: nil}) == []
    end
  end

  describe "school_timetable/1" do
    test "groups the year's slots by class, with the subject's code", ctx do
      %{
        scope: scope,
        year: year,
        cg: cg,
        tc_maths: tc_maths,
        tc_eps: tc_eps,
        periods: [p1, p2 | _]
      } =
        ctx

      scope = %{scope | current_academic_year: year}

      {:ok, maths} =
        Ash.get(TeacherAssistant.Academics.Subject, tc_maths.subject_id, scope: scope)

      {:ok, _} = Curriculum.update_subject(scope, maths, %{code: "MATH"})

      for {p, tc} <- [{p1, tc_maths}, {p2, tc_eps}] do
        {:ok, _} =
          Timetabling.place_slot(scope, cg, %{
            day: :monday,
            period_id: p.id,
            teaching_context_id: tc.id
          })
      end

      grid = Timetabling.school_timetable(scope)[cg.id]
      assert [%{subject_code: "MATH", teacher_name: "Jean Abena"}] = grid[{:monday, p1.id}]
      assert [%{subject_code: "EPS"}] = grid[{:monday, p2.id}]
    end

    test "a combined course sits in each of its classes", ctx do
      %{scope: scope, year: year, cg: cg, head: head, tc_maths: tc_maths, periods: [p1 | _]} = ctx
      scope = %{scope | current_academic_year: year}

      {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
      {:ok, tc_b} = Curriculum.assign_teacher(scope, cg_b, head, %{subject: "Maths"})
      {:ok, course} = Curriculum.combine_course(scope, [tc_maths, tc_b])
      {:ok, _} = Timetabling.place_combined_slot(scope, course, :monday, p1.id)

      result = Timetabling.school_timetable(scope)
      assert [_] = result[cg.id][{:monday, p1.id}]
      assert [_] = result[cg_b.id][{:monday, p1.id}]
    end

    test "is empty without a current year", ctx do
      assert Timetabling.school_timetable(%{ctx.scope | current_academic_year: nil}) == %{}
    end
  end
end
