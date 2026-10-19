defmodule TeacherAssistant.Academics.TeacherUnavailabilityTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    teacher = TeacherFixtures.user_fixture()
    TeacherFixtures.membership_fixture(scope, %{user: teacher})
    %{scope: scope, year: year, p1: p1, p2: p2, t: teacher}
  end

  test "set_unavailable blocks and unblocks cells; unavailability/1 returns them", ctx do
    %{scope: scope, t: t, p1: p1, p2: p2} = ctx
    cells = [{:monday, p1.id}, {:monday, p2.id}]
    assert :ok = Timetabling.set_unavailable(scope, t.id, cells, true)
    assert :ok = Timetabling.set_unavailable(scope, t.id, cells, true)

    assert Timetabling.unavailability(scope) ==
             MapSet.new([{t.id, :monday, p1.id}, {t.id, :monday, p2.id}])

    assert :ok = Timetabling.set_unavailable(scope, t.id, [{:monday, p1.id}], false)
    assert Timetabling.unavailability(scope) == MapSet.new([{t.id, :monday, p2.id}])
  end

  test "a plain teacher can neither read nor write unavailability", ctx do
    %{scope: scope, t: t, p1: p1} = ctx
    :ok = Timetabling.set_unavailable(scope, t.id, [{:monday, p1.id}], true)
    teacher_scope = TeacherFixtures.member_scope_fixture(scope)
    teacher_scope = %{teacher_scope | current_academic_year: ctx.year}

    assert Timetabling.unavailability(teacher_scope) == MapSet.new()

    assert {:error, _} =
             Timetabling.set_unavailable(teacher_scope, t.id, [{:tuesday, p1.id}], true)

    assert MapSet.size(Timetabling.unavailability(scope)) == 1
  end

  test "a user who is not a member, or a foreign period, is refused with :invalid", ctx do
    %{scope: scope, p1: p1} = ctx
    stranger = TeacherFixtures.user_fixture()

    assert {:error, :invalid} =
             Timetabling.set_unavailable(scope, stranger.id, [{:monday, p1.id}], true)

    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    _ = Attendance.build_default_periods(other)
    [fp | _] = Attendance.list_periods(other)

    assert {:error, :invalid} =
             Timetabling.set_unavailable(scope, ctx.t.id, [{:monday, fp.id}], true)

    assert Timetabling.unavailability(scope) == MapSet.new()
  end

  test "a closed year refuses changes", ctx do
    %{scope: scope, t: t, p1: p1, year: year} = ctx
    %{next: _} = TeacherFixtures.close_year!(scope, year)

    TeacherAssistant.Academics.TeacherUnavailability
    |> Ash.Changeset.for_create(
      :create,
      %{academic_year_id: year.id, teacher_user_id: t.id, day: :monday, period_id: p1.id},
      scope: scope
    )
    |> Ash.create()
    |> then(&assert {:error, _} = &1)
  end
end
