defmodule TeacherAssistant.Academics.SubjectTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.Academics.Subjects
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Test"})
    Enum.each(Subjects.list(school), &Subjects.delete/1)
    %{ws: school}
  end

  test "creates a subject with defaults", %{ws: ws} do
    {:ok, s} =
      Subject
      |> Ash.Changeset.for_create(:create, %{name: "Mathématiques", workspace_id: ws.id})
      |> Ash.create(authorize?: false)

    assert s.name == "Mathématiques"
    assert s.category == :general
    assert Decimal.equal?(s.default_coefficient, Decimal.new(1))
    assert s.active? == true
  end

  test "name is unique per workspace", %{ws: ws} do
    attrs = %{name: "Français", workspace_id: ws.id}
    {:ok, _} = Subject |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
    assert {:error, _} = Subject |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end
end
