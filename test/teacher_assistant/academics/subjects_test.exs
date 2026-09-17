defmodule TeacherAssistant.Academics.SubjectsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Subjects
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})
    %{ws: ws}
  end

  test "create then list, ordered", %{ws: ws} do
    {:ok, _} = Subjects.create(ws, %{name: "Français", position: 2})
    {:ok, _} = Subjects.create(ws, %{name: "Mathématiques", position: 1})
    assert ["Mathématiques", "Français"] = Enum.map(Subjects.list(ws), & &1.name)
  end

  test "duplicate name is a tagged error", %{ws: ws} do
    {:ok, _} = Subjects.create(ws, %{name: "Anglais"})
    assert {:error, :duplicate_name} = Subjects.create(ws, %{name: "Anglais"})
  end

  test "deactivate and delete", %{ws: ws} do
    {:ok, s} = Subjects.create(ws, %{name: "EPS"})
    {:ok, s} = Subjects.deactivate(s)
    refute s.active?
    assert :ok = Subjects.delete(s)
    assert Subjects.list(ws) == []
  end
end
