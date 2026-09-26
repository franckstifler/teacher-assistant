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
    assert s.category == :general
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
end
