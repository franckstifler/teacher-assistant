defmodule TeacherAssistant.Academics.ConductTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Conduct
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Accounts.Schools

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

  describe "period_date_range/1" do
    setup do
      head = TeacherAssistant.TeacherFixtures.user_fixture()
      {:ok, school} = Schools.create_school(head, %{name: "Lycée P"})

      {:ok, year} =
        Academics.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = Academics.build_default_calendar(year)

      %{year: year}
    end

    test "returns the séquence's own dates for {:sequence, seq}", %{year: year} do
      [seq | _] = Academics.list_sequences(year)

      assert Academics.period_date_range({:sequence, seq}) == {seq.start_date, seq.end_date}
    end

    test "returns min-start/max-end across the term's séquences for {:trimester, term}", %{
      year: year
    } do
      [term1 | _] = Academics.list_terms(year)

      expected_first = term1.sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
      expected_last = term1.sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)

      assert Academics.period_date_range({:trimester, term1}) == {expected_first, expected_last}
    end

    test "returns min-start/max-end across the year's séquences for {:annual, year}", %{
      year: year
    } do
      sequences = Academics.list_sequences(year)

      expected_first = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
      expected_last = sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)

      assert Academics.period_date_range({:annual, year}) == {expected_first, expected_last}
    end
  end
end
