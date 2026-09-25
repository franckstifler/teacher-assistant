defmodule TeacherAssistant.Academics.TimetablesPeriodsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Test"
      })

    %{school: school, scope: school_scope(user, school)}
  end

  test "build_default_periods seeds a sorted bell schedule with breaks and lessons", %{
    school: _school,
    scope: scope
  } do
    assert :ok = Attendance.build_default_periods(scope)

    periods = Attendance.list_periods(scope)
    assert periods != []
    assert Enum.map(periods, & &1.position) == Enum.sort(Enum.map(periods, & &1.position))

    first = List.first(periods)
    assert first.start_time == ~T[07:30:00]

    assert Enum.any?(periods, &(&1.kind == :break))
    assert Enum.count(periods, &(&1.kind == :lesson)) >= 5
  end

  test "build_default_periods is idempotent", %{scope: scope} do
    :ok = Attendance.build_default_periods(scope)
    count_after_first = length(Attendance.list_periods(scope))

    assert :ok = Attendance.build_default_periods(scope)
    assert length(Attendance.list_periods(scope)) == count_after_first
  end

  test "a new school is created with the default bell schedule" do
    user = TeacherFixtures.user_fixture()

    {:ok, other_school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Other School"
      })

    assert Attendance.list_periods(school_scope(user, other_school)) != []
  end
end
