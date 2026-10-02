defmodule TeacherAssistant.Academics.RosterLineTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.RosterLine

  test "reads the seven columns, all but the name optional" do
    [full, short] =
      RosterLine.parse("""
      Awa Nkolo;f;M-001;02/04/2013;Yaoundé;Jean Nkolo;677 12 34 56
      Paul Mbarga;m
      """)

    assert full == %{
             full_name: "Awa Nkolo",
             sex: :f,
             matricule: "M-001",
             repeater: false,
             birth_date: ~D[2013-04-02],
             birth_place: "Yaoundé",
             guardian: %{full_name: "Jean Nkolo", phone: "677 12 34 56"}
           }

    assert %{full_name: "Paul Mbarga", sex: :m, birth_date: nil, guardian: nil} = short
  end

  test "an impossible date is dropped, the row is kept" do
    assert [%{full_name: "Awa", birth_date: nil}] = RosterLine.parse("Awa;f;;31/02/2010")
    assert [%{birth_date: nil}] = RosterLine.parse("Awa;f;;2010")
  end

  test "a phone without a name still makes a guardian named after the student's family" do
    assert [%{guardian: %{full_name: "Parent de Awa Nkolo", phone: "677123456"}}] =
             RosterLine.parse("Awa Nkolo;f;;;;;677123456")
  end
end
