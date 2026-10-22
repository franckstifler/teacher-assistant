defmodule TeacherAssistant.Academics.BulletinV2DataTest do
  @moduledoc "Bulletin & card v2 (spec 2026-10-21 §4): the new data."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Enrollment, MarksFixtures, TeacherFixtures}
  alias TeacherAssistant.Academics.{BulletinElement, SequenceCompetence}

  defp update_profile(scope, attrs) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    profile |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  defp upsert(scope, tc, seq, text) do
    SequenceCompetence
    |> Ash.Changeset.for_create(
      :upsert,
      %{teaching_context_id: tc.id, sequence_id: seq.id, text: text},
      scope: scope
    )
    |> Ash.create()
  end

  test "profile stores school code, English name and English header lines; blanks become nil" do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()

    assert {:ok, p} =
             update_profile(head, %{
               school_code: " 5MN1TEF110431106 ",
               name_en: "G.T.H.S Ngog-Mapubi"
             })

    assert p.school_code == "5MN1TEF110431106"
    assert p.name_en == "G.T.H.S Ngog-Mapubi"

    assert {:ok, p} =
             Accounts.update_official_header(head, %{
               official_header_lines_en: ["Republic of Cameroon"]
             })

    assert p.official_header_lines_en == ["Republic of Cameroon"]

    assert {:ok, p} = update_profile(head, %{school_code: "  ", name_en: " "})
    assert p.school_code == nil
    assert p.name_en == nil
  end

  test "student national_id is optional and trimmed" do
    %{head: head, cg: cg} = MarksFixtures.marks_world()

    {:ok, s} =
      Enrollment.add_student(head, cg, %{full_name: "Nlend", sex: :f, national_id: " 241592812 "})

    assert s.national_id == "241592812"

    {:ok, s} = Enrollment.add_student(head, cg, %{full_name: "Eyong", sex: :m})
    assert s.national_id == nil
  end

  test "competence upsert keeps one row per context and sequence" do
    %{t: t, tc: tc, seq: seq} = MarksFixtures.marks_world()

    assert {:ok, _} = upsert(t, tc, seq, "Additionner, soustraire")
    assert {:ok, _} = upsert(t, tc, seq, "Calculer un pourcentage")

    assert [%{text: "Calculer un pourcentage"}] = Ash.read!(SequenceCompetence, scope: t)
  end

  test "competence text longer than 140 is refused" do
    %{t: t, tc: tc, seq: seq} = MarksFixtures.marks_world()

    assert {:error, %Ash.Error.Invalid{}} = upsert(t, tc, seq, String.duplicate("a", 141))
    assert {:ok, _} = upsert(t, tc, seq, String.duplicate("a", 140))
  end

  test "only the context's teacher or an admin writes a competence" do
    %{head: head, t: t, tc: tc, seq: seq} = MarksFixtures.marks_world()
    %{scope: other} = TeacherFixtures.school_teacher_fixture(head, %{subject: "Anglais"})

    # A create rule on a relationship is « maybe » for `Ash.can?`: test the real writes.
    assert {:ok, _} = upsert(t, tc, seq, "par l'enseignant")
    assert {:ok, _} = upsert(head, tc, seq, "par l'admin")
    assert {:error, %Ash.Error.Forbidden{}} = upsert(other, tc, seq, "intrus")
  end

  test "defaults exclude qr_code and apc" do
    refute :apc in BulletinElement.defaults()
    refute :qr_code in BulletinElement.defaults()
    assert :previous_terms in BulletinElement.defaults()
    assert :annual_summary in BulletinElement.defaults()

    for el <-
          [:apc, :previous_terms, :annual_summary, :guardians, :national_id] ++
            [:class_profile, :teacher_visa],
        do: assert(is_binary(BulletinElement.label(el)))
  end

  test "an appreciation band accepts a code" do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()

    assert {:ok, p} =
             update_profile(head, %{
               appreciation_bands: [
                 %{from: Decimal.new(0), label: "C. non acquise", code: "CNA"},
                 %{from: Decimal.new(10), label: "C. acquise", code: "CA"}
               ]
             })

    assert Enum.map(p.appreciation_bands, & &1.code) == ["CNA", "CA"]
  end
end
