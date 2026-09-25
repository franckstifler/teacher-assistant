defmodule TeacherAssistant.Academics.ConductTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Conduct
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Organization

  describe "period_hours/1" do
    test "computes hours as a Decimal for a 07:30-08:25 period" do
      period = %Period{start_time: ~T[07:30:00], end_time: ~T[08:25:00]}

      expected =
        Decimal.div(Decimal.new(Time.diff(~T[08:25:00], ~T[07:30:00], :minute)), Decimal.new(60))

      assert Decimal.equal?(Conduct.period_hours(period), expected)
    end

    test "computes hours for a two-hour period" do
      period = %Period{start_time: ~T[08:00:00], end_time: ~T[10:00:00]}

      assert Decimal.equal?(Conduct.period_hours(period), Decimal.new(2))
    end
  end

  describe "totals/1" do
    test "sums justified/unjustified absence hours and counts retards" do
      one_hour_period = %Period{start_time: ~T[08:00:00], end_time: ~T[09:00:00]}

      entries = [
        %{status: :absent, justified: true, period: one_hour_period},
        %{status: :absent, justified: false, period: one_hour_period},
        %{status: :late, justified: false, period: one_hour_period},
        %{status: :late, justified: false, period: one_hour_period},
        %{status: :present, justified: false, period: one_hour_period}
      ]

      totals = Conduct.totals(entries)

      assert Decimal.equal?(totals.justified_hours, Decimal.new(1))
      assert Decimal.equal?(totals.unjustified_hours, Decimal.new(1))
      assert totals.retards == 2
    end

    test "empty list yields zeros" do
      totals = Conduct.totals([])

      assert Decimal.equal?(totals.justified_hours, Decimal.new(0))
      assert Decimal.equal?(totals.unjustified_hours, Decimal.new(0))
      assert totals.retards == 0
    end
  end

  describe "period_date_range/2" do
    setup do
      head = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, school} =
        Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée P"})

      scope = school_scope(head, school)

      {:ok, year} =
        Organization.create_academic_year(scope, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = Organization.build_default_calendar(scope, year)

      %{year: year, scope: scope}
    end

    test "returns the séquence's own dates for {:sequence, seq}", %{year: year, scope: scope} do
      [seq | _] = Organization.list_sequences(scope, year)

      assert Organization.period_date_range(scope, {:sequence, seq}) ==
               {seq.start_date, seq.end_date}
    end

    test "returns min-start/max-end across the term's séquences for {:trimester, term}", %{
      year: year,
      scope: scope
    } do
      [term1 | _] = Organization.list_terms(scope, year)

      expected_first = term1.sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
      expected_last = term1.sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)

      assert Organization.period_date_range(scope, {:trimester, term1}) ==
               {expected_first, expected_last}
    end

    test "returns min-start/max-end across the year's séquences for {:annual, year}", %{
      year: year,
      scope: scope
    } do
      sequences = Organization.list_sequences(scope, year)

      expected_first = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
      expected_last = sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)

      assert Organization.period_date_range(scope, {:annual, year}) ==
               {expected_first, expected_last}
    end
  end
end
