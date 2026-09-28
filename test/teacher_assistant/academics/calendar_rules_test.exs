defmodule TeacherAssistant.Academics.CalendarRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.CalendarRules

  @year %{start_date: ~D[2026-09-07], end_date: ~D[2027-06-30]}

  defp seq(n, term, start_date, end_date, deadline \\ nil),
    do: %{
      id: "s#{n}",
      number: n,
      term_id: term,
      start_date: start_date,
      end_date: end_date,
      entry_deadline: deadline
    }

  defp valid_seqs,
    do: [
      seq(1, "t1", ~D[2026-09-07], ~D[2026-10-02]),
      seq(2, "t1", ~D[2026-10-05], ~D[2026-11-13])
    ]

  defp errors(result) do
    assert {:error, {:invalid, errors}} = result
    errors
  end

  test "a coherent calendar passes, with gaps between séquences allowed" do
    assert :ok =
             CalendarRules.validate(@year, valid_seqs(), [%{id: "t1", class_council_date: nil}])
  end

  test "missing and unparseable dates are reported per field" do
    [s1, s2] = valid_seqs()
    seqs = [%{s1 | start_date: nil}, %{s2 | end_date: :invalid}]
    errs = errors(CalendarRules.validate(@year, seqs, []))
    assert {:start_date, :required} in errs["s1"]
    assert {:end_date, :invalid_date} in errs["s2"]
  end

  test "an end before its start is rejected" do
    [s1, s2] = valid_seqs()
    errs = errors(CalendarRules.validate(@year, [%{s1 | end_date: ~D[2026-09-01]}, s2], []))
    assert {:end_date, :end_before_start} in errs["s1"]
  end

  test "séquences must stay inside the academic year" do
    [s1, s2] = valid_seqs()
    seqs = [%{s1 | start_date: ~D[2026-09-01]}, %{s2 | end_date: ~D[2027-07-15]}]
    errs = errors(CalendarRules.validate(@year, seqs, []))
    assert {:start_date, :outside_year} in errs["s1"]
    assert {:end_date, :outside_year} in errs["s2"]
  end

  test "a séquence must start after the previous one ends" do
    [s1, s2] = valid_seqs()
    errs = errors(CalendarRules.validate(@year, [s1, %{s2 | start_date: ~D[2026-10-02]}], []))
    assert {:start_date, :overlaps_previous} in errs["s2"]
  end

  test "an explicit deadline cannot precede the séquence end, even after the end moves" do
    [s1, s2] = valid_seqs()
    moved = %{s1 | end_date: ~D[2026-10-02], entry_deadline: ~D[2026-10-01]}
    errs = errors(CalendarRules.validate(@year, [moved, s2], []))
    assert {:entry_deadline, :deadline_before_end} in errs["s1"]
  end

  test "a class council cannot precede the end of its trimester" do
    terms = [%{id: "t1", class_council_date: ~D[2026-11-10]}]
    errs = errors(CalendarRules.validate(@year, valid_seqs(), terms))
    assert {:class_council_date, :council_before_term_end} in errs["t1"]

    assert errors(
             CalendarRules.validate(@year, valid_seqs(), [
               %{id: "t1", class_council_date: :invalid}
             ])
           )["t1"] ==
             [{:class_council_date, :invalid_date}]
  end
end
