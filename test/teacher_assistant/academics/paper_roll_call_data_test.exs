defmodule TeacherAssistant.Academics.PaperRollCallDataTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, TeacherFixtures}
  alias TeacherAssistant.Academics.{ClassGroup, LessonNotHeld}

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    %{scope: scope, year: year, cg: cg, tc: tc, e: e, p1: p1, sg: sg, teacher: teacher}
  end

  test "a new class is on paper by default", %{cg: cg} do
    assert cg.paper_roll_call == true
  end

  test "a surveillant switches one class off; a teacher may not",
       %{cg: cg, sg: sg, teacher: teacher} do
    assert_forbidden(Enrollment.set_paper_roll_call(teacher, cg, false))

    assert {:ok, %ClassGroup{paper_roll_call: false}} =
             Enrollment.set_paper_roll_call(sg, cg, false)
  end

  test "the school-wide switch sets every class of the year", %{scope: scope, year: year, cg: cg} do
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert :ok = Attendance.set_paper_roll_call_all(scope, year, false)
      end)

    refute log =~ "Missed"

    for class <- [cg, other] do
      {:ok, reloaded} = Enrollment.fetch_owned_class_group(scope, class.id)
      refute reloaded.paper_roll_call
    end
  end

  test "an entry is from the app unless said otherwise",
       %{scope: scope, cg: cg, tc: tc, e: e, p1: p1} do
    {:ok, 1} = Attendance.record_period(scope, cg, p1, tc, ~D[2025-09-15], [{e.id, :present}])
    [entry] = Attendance.for_class_range!(cg.id, ~D[2025-09-15], ~D[2025-09-15], scope: scope)
    assert entry.source == :app
  end

  test "a lesson is marked not held once", %{cg: cg, p1: p1, sg: sg, teacher: teacher} do
    attrs = %{class_group_id: cg.id, period_id: p1.id, date: ~D[2025-09-15]}

    assert {:ok, %LessonNotHeld{} = lesson} =
             LessonNotHeld |> Ash.Changeset.for_create(:mark, attrs, scope: sg) |> Ash.create()

    assert lesson.marked_by_user_id == sg.current_user.id

    assert {:error, _} =
             LessonNotHeld |> Ash.Changeset.for_create(:mark, attrs, scope: sg) |> Ash.create()

    assert_forbidden(
      LessonNotHeld
      |> Ash.Changeset.for_create(:mark, %{attrs | date: ~D[2025-09-16]}, scope: teacher)
      |> Ash.create()
    )
  end
end
