defmodule TeacherAssistant.Academics.RosterLineTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.RosterLine

  test "reads the five columns, padding short lines" do
    [full, short] =
      RosterLine.parse("""
      Awa Nkolo ; F ; M-001 ; 02/04/2013 ; 677 12 34 56
      Paul Mbarga;m
      """)

    assert full == %{
             full_name: "Awa Nkolo",
             sex: :f,
             matricule: "M-001",
             repeater: false,
             birth_date: ~D[2013-04-02],
             guardian: %{full_name: "Parent de Awa Nkolo", phone: "677 12 34 56"}
           }

    assert %{full_name: "Paul Mbarga", sex: :m, matricule: nil, birth_date: nil, guardian: nil} =
             short
  end

  test "a line with a tab splits on tabs (a semicolon in a name is kept)" do
    assert [%{full_name: "Awa; Nkolo", sex: :f, matricule: "M-1"}] =
             RosterLine.parse("Awa; Nkolo\tf\tM-1")
  end

  test "sex synonyms, any case; blank or unknown is nil" do
    sexes =
      ~w(M g Garçon garcon B boy male F fille GIRL female x)
      |> Enum.map(&RosterLine.parse("Awa;#{&1}"))
      |> Enum.map(fn [row] -> row.sex end)

    assert sexes == [:m, :m, :m, :m, :m, :m, :m, :f, :f, :f, :f, nil]
    assert [%{sex: nil}] = RosterLine.parse("Awa")
  end

  test "blank-name lines are dropped" do
    assert [%{full_name: "Awa"}] = RosterLine.parse("Awa;f\n ;m\n\n")
  end

  test "an impossible or future date is dropped, the row is kept" do
    assert [%{full_name: "Awa", birth_date: nil}] = RosterLine.parse("Awa;f;;31/02/2010")
    assert [%{birth_date: nil}] = RosterLine.parse("Awa;f;;2010")

    future = Date.utc_today() |> Date.add(400) |> Calendar.strftime("%d/%m/%Y")
    assert [%{full_name: "Awa", birth_date: nil}] = RosterLine.parse("Awa;f;;#{future}")
  end
end
