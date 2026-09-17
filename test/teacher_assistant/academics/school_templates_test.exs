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
end
