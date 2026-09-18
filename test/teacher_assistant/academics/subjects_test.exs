defmodule TeacherAssistant.Academics.SubjectsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Organization.create_school(head, %{name: "Lycée Test"})
    Enum.each(Curriculum.list_subjects(ws), &Curriculum.delete_subject/1)
    %{ws: ws}
  end

  test "create then list, ordered", %{ws: ws} do
    {:ok, _} = Curriculum.create_subject(ws, %{name: "Français", position: 2})
    {:ok, _} = Curriculum.create_subject(ws, %{name: "Mathématiques", position: 1})
    assert ["Mathématiques", "Français"] = Enum.map(Curriculum.list_subjects(ws), & &1.name)
  end

  test "duplicate name is a tagged error", %{ws: ws} do
    {:ok, _} = Curriculum.create_subject(ws, %{name: "Anglais"})
    assert {:error, :duplicate_name} = Curriculum.create_subject(ws, %{name: "Anglais"})
  end

  test "deactivate and delete", %{ws: ws} do
    {:ok, s} = Curriculum.create_subject(ws, %{name: "EPS"})
    {:ok, s} = Curriculum.deactivate_subject(s)
    refute s.active?
    assert :ok = Curriculum.delete_subject(s)
    assert Curriculum.list_subjects(ws) == []
  end
end
