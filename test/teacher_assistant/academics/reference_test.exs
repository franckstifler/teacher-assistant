defmodule TeacherAssistant.Academics.ReferenceTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Reference

  test "subsystems are francophone and anglophone with bilingual labels" do
    keys = Enum.map(Reference.subsystems(), & &1.key)
    assert keys == [:francophone, :anglophone]
    assert Enum.all?(Reference.subsystems(), &(&1.fr != "" and &1.en != ""))
  end

  test "francophone levels run 6ème to Terminale" do
    assert Reference.levels(:francophone) |> List.first() == "6ème"
    assert Reference.levels(:francophone) |> List.last() == "Terminale"
  end

  test "anglophone levels run Form 1 to Upper Sixth" do
    assert Reference.levels(:anglophone) |> List.first() == "Form 1"
    assert Reference.levels(:anglophone) |> List.last() == "Upper Sixth"
  end

  test "entry types include lesson and integration" do
    assert :lesson in Reference.entry_type_keys()
    assert :integration in Reference.entry_type_keys()
  end

  test "default calendar preset has 3 terms and 6 sequences" do
    preset = Reference.default_calendar_preset()
    assert length(preset.terms) == 3
    seqs = Enum.flat_map(preset.terms, & &1.sequences)
    assert length(seqs) == 6
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
  end
end
