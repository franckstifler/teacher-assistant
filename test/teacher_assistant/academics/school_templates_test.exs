defmodule TeacherAssistant.Academics.SchoolTemplatesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.SchoolTemplates, as: T

  test "francophone lycée: general levels + séries at 2nde+" do
    assert "6ème" in T.levels_for(:lycee, :francophone)
    assert "Terminale" in T.levels_for(:lycee, :francophone)
    %{kind: :serie, values: values, levels: levels} = T.streams_for(:lycee, :francophone)
    assert "C" in values and "D" in values
    assert "2nde" in levels
    refute "6ème" in levels
  end

  test "cetic: specialities as streams" do
    %{kind: :specialite, values: values} = T.streams_for(:cetic, :francophone)
    assert "ELEQ" in values and "MACO" in values
    assert T.stream_label(:specialite) == "Spécialité"
  end

  test "anglophone GBHS: Forms + Arts/Science stream at Sixth" do
    assert "Form 1" in T.levels_for(:gbhs, :anglophone)
    %{values: values} = T.streams_for(:gbhs, :anglophone)
    assert "Science" in values
  end

  test "subjects include general + coefficients" do
    subs = T.subjects_for(:lycee, :francophone)
    assert Enum.any?(subs, &(&1.name == "Mathématiques"))
    maths = Enum.find(subs, &(&1.name == "Mathématiques"))
    assert Decimal.equal?(maths.default_coefficient, Decimal.new(4))
  end

  test "classes_for produces one class per level and per streamed level×stream" do
    classes = T.classes_for(:lycee, :francophone)
    assert Enum.any?(classes, &(&1.level == "6ème" and is_nil(&1.serie)))
    assert Enum.any?(classes, &(&1.level == "2nde" and &1.serie == "C"))
  end

  test "technical schools (:gtc, :gths) get specialities not séries/streams" do
    # Francophone technical school
    streams_gtc = T.streams_for(:gtc, :francophone)
    assert streams_gtc.kind == :specialite
    assert "ELEQ" in streams_gtc.values and "MACO" in streams_gtc.values

    # Levels should match levels_for, not general levels
    assert streams_gtc.levels == T.levels_for(:gtc, :francophone)
    assert "1ère Année" in streams_gtc.levels
    refute "6ème" in streams_gtc.levels

    # Anglophone technical school
    streams_gths = T.streams_for(:gths, :anglophone)
    assert streams_gths.kind == :specialite
    assert "ELEQ" in streams_gths.values and "MACO" in streams_gths.values

    # Levels should be technical years, not anglophone forms
    assert streams_gths.levels == T.levels_for(:gths, :anglophone)
    assert "1ère Année" in streams_gths.levels
    refute "Form 1" in streams_gths.levels

    # Both have technical subjects
    subjects_gtc = T.subjects_for(:gtc, :francophone)
    subjects_gths = T.subjects_for(:gths, :anglophone)

    assert Enum.any?(subjects_gtc, &(&1.name == "Atelier / Pratique"))
    assert Enum.any?(subjects_gths, &(&1.name == "Atelier / Pratique"))

    # classes_for should not have speciality classes at general levels
    classes_gtc = T.classes_for(:gtc, :francophone)
    refute Enum.any?(classes_gtc, &(&1.level == "6ème"))
    assert Enum.any?(classes_gtc, &(&1.level == "1ère Année" and &1.serie == "ELEQ"))

    classes_gths = T.classes_for(:gths, :anglophone)
    refute Enum.any?(classes_gths, &(&1.level == "Form 1"))
    assert Enum.any?(classes_gths, &(&1.level == "1ère Année" and &1.serie == "ELEQ"))
  end
end
