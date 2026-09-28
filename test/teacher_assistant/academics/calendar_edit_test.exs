defmodule TeacherAssistant.Academics.CalendarEditTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [s1, s2 | _] = Organization.list_sequences(scope, year)
    [t1 | _] = Organization.list_terms(scope, year)
    %{scope: scope, year: year, s1: s1, s2: s2, t1: t1}
  end

  defp iso(date), do: Date.to_iso8601(date)

  test "saves dates, an explicit deadline and a council date", ctx do
    %{scope: scope, year: year, s1: s1, s2: s2, t1: t1} = ctx

    params = %{
      "sequences" => %{
        s1.id => %{
          "end_date" => iso(Date.add(s1.end_date, -3)),
          "entry_deadline" => iso(s1.end_date)
        }
      },
      "terms" => %{t1.id => %{"class_council_date" => iso(Date.add(s2.end_date, 4))}}
    }

    assert :ok = Organization.update_calendar(scope, year, params)
    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.end_date == Date.add(s1.end_date, -3)
    assert u1.grade_entry_deadline == s1.end_date
    assert hd(Organization.list_terms(scope, year)).class_council_date == Date.add(s2.end_date, 4)
  end

  test "clearing a deadline falls back to the default rule", %{scope: scope, year: year, s1: s1} do
    :ok =
      Organization.update_calendar(scope, year, %{
        "sequences" => %{s1.id => %{"entry_deadline" => iso(Date.add(s1.end_date, 9))}}
      })

    :ok =
      Organization.update_calendar(scope, year, %{"sequences" => %{s1.id => %{"entry_deadline" => ""}}})

    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.entry_deadline == nil
    assert u1.grade_entry_deadline == Date.add(u1.end_date, 5)
  end

  test "an incoherent calendar is rejected and nothing is written", ctx do
    %{scope: scope, year: year, s1: s1, s2: s2} = ctx

    params = %{
      "sequences" => %{
        s1.id => %{"entry_deadline" => iso(Date.add(s1.end_date, 2))},
        s2.id => %{"start_date" => iso(s1.end_date)}
      }
    }

    assert {:error, {:invalid, errors}} = Organization.update_calendar(scope, year, params)
    assert {:start_date, :overlaps_previous} in errors[s2.id]
    [u1, u2 | _] = Organization.list_sequences(scope, year)
    assert u1.entry_deadline == nil
    assert u2.start_date == s2.start_date
  end

  test "an unparseable date is reported, not raised", %{scope: scope, year: year, s1: s1} do
    assert {:error, {:invalid, errors}} =
             Organization.update_calendar(scope, year, %{
               "sequences" => %{s1.id => %{"end_date" => "31/12/2025"}}
             })

    assert {:end_date, :invalid_date} in errors[s1.id]
  end

  test "a year without a calendar saves as a no-op", %{scope: scope} do
    {:ok, bare} =
      Organization.create_academic_year(scope, %{
        name: "2027-2028",
        start_date: ~D[2027-09-06],
        end_date: ~D[2028-07-28],
        active: false
      })

    assert :ok = Organization.update_calendar(scope, bare, %{})
  end

  test "a teacher cannot change the calendar", %{scope: scope, year: year, s1: s1} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    params = %{"sequences" => %{s1.id => %{"end_date" => iso(Date.add(s1.end_date, -1))}}}
    assert_forbidden(Organization.update_calendar(teacher, year, params))
    assert hd(Organization.list_sequences(scope, year)).end_date == s1.end_date
  end
end
