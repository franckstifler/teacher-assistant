defmodule TeacherAssistant.Academics.TimetablesPeriodsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Test"})
    %{school: school}
  end

  test "build_default_periods seeds a sorted bell schedule with breaks and lessons", %{
    school: school
  } do
    assert :ok = Timetables.build_default_periods(school)

    periods = Timetables.list_periods(school)
    assert periods != []
    assert Enum.map(periods, & &1.position) == Enum.sort(Enum.map(periods, & &1.position))

    first = List.first(periods)
    assert first.start_time == ~T[07:30:00]

    assert Enum.any?(periods, &(&1.kind == :break))
    assert Enum.count(periods, &(&1.kind == :lesson)) >= 5
  end

  test "build_default_periods is idempotent", %{school: school} do
    :ok = Timetables.build_default_periods(school)
    count_after_first = length(Timetables.list_periods(school))

    assert :ok = Timetables.build_default_periods(school)
    assert length(Timetables.list_periods(school)) == count_after_first
  end

  test "list_periods returns [] for an unseeded workspace" do
    user = TeacherFixtures.user_fixture()
    {:ok, other_school} = Schools.create_school(user, %{name: "Other School"})

    assert Timetables.list_periods(other_school) == []
  end
end
