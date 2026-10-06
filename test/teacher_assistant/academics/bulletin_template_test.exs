defmodule TeacherAssistant.Academics.BulletinTemplateTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{BulletinTemplate, ClassGroup}
  alias TeacherAssistant.Accounts.SchoolProfile

  defp profile(attrs \\ %{}) do
    struct(
      SchoolProfile,
      Map.merge(
        %{
          bulletin_language: :by_class,
          bulletin_elements: nil,
          grade_scale: nil,
          region: :littoral,
          department: "Wouri",
          town: "Douala",
          address: "BP 12",
          phone: "+237 233 00 00 00",
          motto: "Travail",
          registration_number: "123/MINESEC",
          logo_path: nil
        },
        attrs
      )
    )
  end

  test "language follows the class, or bilingual for every class" do
    fr = %ClassGroup{subsystem: :francophone}
    en = %ClassGroup{subsystem: :anglophone}

    assert %{language: :fr, grading: :appreciation} = BulletinTemplate.resolve(profile(), "L", fr)
    assert %{language: :en, grading: :grade} = BulletinTemplate.resolve(profile(), "L", en)

    bi = profile(%{bulletin_language: :bilingual})
    assert %{language: :bilingual, grading: :appreciation} = BulletinTemplate.resolve(bi, "L", fr)
    assert %{language: :bilingual, grading: :grade} = BulletinTemplate.resolve(bi, "L", en)
  end

  test "a class without a sub-system is francophone" do
    assert %{language: :fr} =
             BulletinTemplate.resolve(profile(), "L", %ClassGroup{subsystem: nil})
  end

  test "elements: nil is the defaults, [] stays empty" do
    t = BulletinTemplate.resolve(profile(), "L", %ClassGroup{subsystem: :francophone})
    assert BulletinTemplate.show?(t, :rank)
    refute BulletinTemplate.show?(t, :qr_code)

    t = BulletinTemplate.resolve(profile(%{bulletin_elements: []}), "L", %ClassGroup{})
    refute BulletinTemplate.show?(t, :rank)
  end

  test "header is plain data from the profile" do
    t = BulletinTemplate.resolve(profile(), "Lycée de Bonabéri", %ClassGroup{})

    assert t.header == %{
             name: "Lycée de Bonabéri",
             address: "BP 12",
             town: "Douala",
             phone: "+237 233 00 00 00",
             motto: "Travail",
             registration_number: "123/MINESEC",
             region: :littoral,
             department: "Wouri",
             logo?: false,
             official_lines: nil,
             signature?: false,
             stamp?: false
           }
  end

  test "grade lookup: the highest band whose bound is met; 20 is in the last band" do
    scale = BulletinTemplate.default_grade_scale()
    assert %{letter: "F", remark: "Fail"} = BulletinTemplate.grade(scale, Decimal.new("7.99"))
    assert %{letter: "D"} = BulletinTemplate.grade(scale, Decimal.new(10))
    assert %{letter: "A"} = BulletinTemplate.grade(scale, Decimal.new(20))
    assert BulletinTemplate.grade(scale, nil) == nil
  end

  test "official lines, in the current locale, with the region's delegation" do
    t = BulletinTemplate.resolve(profile(), "L", %ClassGroup{})

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "fr", fn ->
      lines = BulletinTemplate.official_lines(t.header)
      assert "République du Cameroun" in lines
      assert "Délégation régionale des Enseignements secondaires du Littoral" in lines
      assert Enum.any?(lines, &(&1 =~ "Wouri"))
    end)

    no_dept = %{t.header | department: nil}
    refute Enum.any?(BulletinTemplate.official_lines(no_dept), &(&1 =~ "départementale"))
  end

  test "school lines skip what the profile leaves empty" do
    t = BulletinTemplate.resolve(profile(%{motto: nil, phone: ""}), "L", %ClassGroup{})
    lines = BulletinTemplate.school_lines(t.header)
    assert "L" in lines
    refute Enum.any?(lines, &(&1 in [nil, ""]))
  end
end
