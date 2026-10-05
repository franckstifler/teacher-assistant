defmodule TeacherAssistant.Academics.BulletinSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "defaults: follow the class, all elements but the QR, the common grade scale", %{
    scope: scope
  } do
    s = Assessment.bulletin_settings(scope)
    assert s.language == :by_class
    refute :qr_code in s.elements
    assert :rank in s.elements and :pp_signature in s.elements
    assert :birth in s.elements
    assert length(s.elements) == 9
    assert Enum.map(s.grade_scale, & &1.letter) == ~w(F E D C B A)
    refute s.custom_scale?
  end

  test "saves the language and the elements; an empty selection stays empty", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "bilingual",
               "elements" => ["rank", "qr_code", "rank", ""]
             })

    s = Assessment.bulletin_settings(scope)
    assert s.language == :bilingual
    assert s.elements == [:rank, :qr_code]

    assert {:ok, _} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "by_class",
               "elements" => [""]
             })

    assert Assessment.bulletin_settings(scope).elements == []
  end

  test "unknown language or element is refused and nothing is written", %{scope: scope} do
    assert {:error, :invalid_setting} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "klingon",
               "elements" => []
             })

    assert {:error, :invalid_setting} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "by_class",
               "elements" => ["rank", "photo"]
             })

    assert Assessment.bulletin_settings(scope).language == :by_class
  end

  test "saves a grade scale; bounds accept a comma; reset goes back to the default", %{
    scope: scope
  } do
    rows = [
      %{from: "0", letter: "F", remark: "Fail"},
      %{from: "9,5", letter: "P", remark: "Pass"},
      %{from: "15", letter: "A", remark: "Excellent"}
    ]

    assert {:ok, _} = Assessment.update_grade_scale(scope, rows)
    s = Assessment.bulletin_settings(scope)
    assert s.custom_scale?

    assert Enum.map(s.grade_scale, &{Decimal.to_string(&1.from), &1.letter}) ==
             [{"0", "F"}, {"9.5", "P"}, {"15", "A"}]

    assert {:ok, _} = Assessment.reset_grade_scale(scope)
    refute Assessment.bulletin_settings(scope).custom_scale?
  end

  test "grade-scale rules", %{scope: scope} do
    bad = [
      [%{from: "1", letter: "F", remark: "Fail"}],
      [%{from: "0", letter: "F", remark: "Fail"}, %{from: "0", letter: "A", remark: "Top"}],
      [%{from: "0", letter: "F", remark: "Fail"}, %{from: "21", letter: "A", remark: "Top"}],
      [%{from: "0", letter: " ", remark: "Fail"}],
      [%{from: "0", letter: "F", remark: ""}]
    ]

    for rows <- bad do
      assert {:error, %Ash.Error.Invalid{}} = Assessment.update_grade_scale(scope, rows)
    end

    assert {:error, :invalid_number} =
             Assessment.update_grade_scale(scope, [%{from: "x", letter: "F", remark: "Fail"}])
  end

  test "a plain teacher cannot save", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assessment.update_bulletin_settings(teacher, %{
               "language" => "bilingual",
               "elements" => []
             })
  end
end
