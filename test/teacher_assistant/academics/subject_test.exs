defmodule TeacherAssistant.Academics.SubjectTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(head, %{name: "Lycée Test"})

    Enum.each(Curriculum.list_subjects(school), &Curriculum.delete_subject(&1, tenant: school.id))

    %{ws: school}
  end

  test "creates a subject with defaults", %{ws: ws} do
    {:ok, s} =
      Subject
      |> Ash.Changeset.for_create(:create, %{name: "Mathématiques"})
      |> Ash.Changeset.set_tenant(ws.id)
      |> Ash.create(authorize?: false)

    assert s.name == "Mathématiques"
    assert s.category == :general
    assert Decimal.equal?(s.default_coefficient, Decimal.new(1))
    assert s.active? == true
  end

  test "name is unique per workspace", %{ws: ws} do
    attrs = %{name: "Français"}

    {:ok, _} =
      Subject
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.set_tenant(ws.id)
      |> Ash.create(authorize?: false)

    assert {:error, _} =
             Subject
             |> Ash.Changeset.for_create(:create, attrs)
             |> Ash.Changeset.set_tenant(ws.id)
             |> Ash.create(authorize?: false)
  end
end
