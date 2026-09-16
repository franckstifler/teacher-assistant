defmodule TeacherAssistant.Academics.TimetablesReadsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})

    {:ok, tc_maths} =
      Assignments.assign(cg, head, %{subject: "Maths", weekly_hours: 5})

    {:ok, tc_eps} =
      Assignments.assign(cg, head, %{subject: "EPS", weekly_hours: 2})

    {:ok, tc_svt} =
      Assignments.assign(cg, head, %{subject: "SVT", weekly_hours: 3})

    :ok = Timetables.build_default_periods(school)

    periods =
      Timetables.list_periods(school)
      |> Enum.filter(&(&1.kind == :lesson))

    %{
      head: head,
      school: school,
      year: year,
      cg: cg,
      tc_maths: tc_maths,
      tc_eps: tc_eps,
      tc_svt: tc_svt,
      periods: periods
    }
  end

  describe "class_timetable/1" do
    test "returns keyed slots and a tally row per assignment", ctx do
      %{cg: cg, tc_maths: tc_maths, tc_eps: tc_eps, tc_svt: tc_svt, periods: periods} = ctx
      [p1, p2, p3 | _] = periods

      {:ok, _} =
        Timetables.place_slot(cg, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetables.place_slot(cg, %{
          day: :tuesday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetables.place_slot(cg, %{
          day: :wednesday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetables.place_slot(cg, %{
          day: :monday,
          period_id: p2.id,
          teaching_context_id: tc_eps.id
        })

      {:ok, _} =
        Timetables.place_slot(cg, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc_eps.id
        })

      result = Timetables.class_timetable(cg)

      assert map_size(result.slots) == 5

      slot_view = Map.fetch!(result.slots, {:monday, p1.id})
      assert slot_view.teaching_context_id == tc_maths.id
      assert slot_view.subject == "Maths"
      assert slot_view.teacher_email == to_string(ctx.head.email)
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
      %{head: head, school: school, year: year, cg: cg_a, tc_maths: tc_maths, periods: periods} =
        ctx

      [p1, p2 | _] = periods

      {:ok, cg_b} =
        Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})

      {:ok, tc_b} = Assignments.assign(cg_b, head, %{subject: "Histoire", weekly_hours: 3})

      {:ok, _} =
        Timetables.place_slot(cg_a, %{
          day: :monday,
          period_id: p1.id,
          teaching_context_id: tc_maths.id
        })

      {:ok, _} =
        Timetables.place_slot(cg_b, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc_b.id
        })

      result = Timetables.teacher_timetable(school, head)

      assert map_size(result) == 2

      cell_a = Map.fetch!(result, {:monday, p1.id})
      assert cell_a.teaching_context_id == tc_maths.id
      assert cell_a.class_label == "6e A"
      assert cell_a.subject == "Maths"

      cell_b = Map.fetch!(result, {:tuesday, p2.id})
      assert cell_b.teaching_context_id == tc_b.id
      assert cell_b.class_label == "6e B"
      assert cell_b.subject == "Histoire"
    end

    test "returns an empty map for a teacher with no slots", ctx do
      %{school: school} = ctx
      other_teacher = TeacherFixtures.user_fixture()

      assert Timetables.teacher_timetable(school, other_teacher) == %{}
    end
  end
end
