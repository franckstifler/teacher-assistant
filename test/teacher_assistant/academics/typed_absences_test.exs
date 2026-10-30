defmodule TeacherAssistant.Academics.TypedAbsencesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.TypedAbsences

  defp seq(id, hours), do: %{sequence_id: id, term_id: nil, hours: Decimal.new(hours)}
  defp term(id, hours), do: %{sequence_id: nil, term_id: id, hours: Decimal.new(hours)}

  @t1 {:term, "t1", ["s1", "s2"]}

  test "per_sequence sums sequences for the term" do
    assert {:ok, hours} =
             TypedAbsences.hours([seq("s1", 2), seq("s2", "1.5")], @t1, :typed_per_sequence)

    assert Decimal.equal?(hours, Decimal.new("3.5"))
  end

  test "per_sequence reads a séquence's own record" do
    assert {:ok, hours} =
             TypedAbsences.hours(
               [seq("s1", 2), seq("s2", 1)],
               {:sequence, "s2"},
               :typed_per_sequence
             )

    assert Decimal.equal?(hours, 1)
  end

  test "per_sequence ignores trimester records" do
    assert TypedAbsences.hours([term("t1", 9)], @t1, :typed_per_sequence) == :none
  end

  test "per_term prefers the term record over sequence records" do
    assert {:ok, hours} =
             TypedAbsences.hours([seq("s1", 2), term("t1", 7)], @t1, :typed_per_term)

    assert Decimal.equal?(hours, 7)
  end

  test "per_term falls back to sequence records" do
    assert {:ok, hours} = TypedAbsences.hours([seq("s1", 2), seq("s2", 3)], @t1, :typed_per_term)
    assert Decimal.equal?(hours, 5)
  end

  test "per_term sequence is none" do
    assert TypedAbsences.hours([seq("s1", 2)], {:sequence, "s1"}, :typed_per_term) == :none
  end

  test "year sums terms and is none when nothing typed" do
    year = {:year, [{"t1", ["s1", "s2"]}, {"t2", ["s3"]}]}

    assert {:ok, hours} =
             TypedAbsences.hours([term("t1", 4), seq("s3", 1)], year, :typed_per_term)

    assert Decimal.equal?(hours, 5)
    assert TypedAbsences.hours([], year, :typed_per_term) == :none
  end

  test "complete? per_sequence needs every sequence" do
    refute TypedAbsences.complete?([seq("s1", 0)], @t1, :typed_per_sequence)
    assert TypedAbsences.complete?([seq("s1", 0), seq("s2", 0)], @t1, :typed_per_sequence)
  end

  test "complete? per_term accepts a term record" do
    assert TypedAbsences.complete?([term("t1", 0)], @t1, :typed_per_term)
    refute TypedAbsences.complete?([seq("s1", 1)], @t1, :typed_per_term)
    assert TypedAbsences.complete?([], {:sequence, "s1"}, :typed_per_term)
  end

  test "complete? for the year needs every term" do
    year = {:year, [{"t1", ["s1"]}, {"t2", ["s2"]}]}
    refute TypedAbsences.complete?([seq("s1", 1)], year, :typed_per_sequence)
    assert TypedAbsences.complete?([seq("s1", 1), seq("s2", 0)], year, :typed_per_sequence)
  end
end
