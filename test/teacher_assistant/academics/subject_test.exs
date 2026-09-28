defmodule TeacherAssistant.Academics.SubjectTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, school)

    Enum.each(Curriculum.list_subjects(scope), &Curriculum.delete_subject(&1, scope: scope))

    %{scope: scope}
  end

  test "creates a subject with defaults", %{scope: scope} do
    {:ok, s} =
      Subject
      |> Ash.Changeset.for_create(:create, %{name: "Mathématiques"})
      |> Ash.create(scope: scope)

    assert s.name == "Mathématiques"
    assert s.bulletin_group == :g3_autres
    assert Decimal.equal?(s.default_coefficient, Decimal.new(1))
    assert s.active? == true
  end

  test "name is unique per workspace", %{scope: scope} do
    attrs = %{name: "Français"}

    {:ok, _} =
      Subject
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create(scope: scope)

    assert {:error, _} =
             Subject
             |> Ash.Changeset.for_create(:create, attrs)
             |> Ash.create(scope: scope)
  end

  test "bulletin groups have labels, short codes and a bulletin order" do
    alias TeacherAssistant.Academics.BulletinGroup

    assert Enum.sort_by([:g3_autres, :g1_lettres, :g2_sciences], &BulletinGroup.rank/1) ==
             [:g1_lettres, :g2_sciences, :g3_autres]

    assert BulletinGroup.short(:g2_sciences) == "G2"
    assert BulletinGroup.label(:g1_lettres) == "Groupe 1 · Lettres"
  end
end
