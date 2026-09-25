defmodule TeacherAssistant.Academics.SubjectsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Organization.create_school(head, %{name: "Lycée Test"})
    scope = school_scope(head, ws)
    Enum.each(Curriculum.list_subjects(scope), &Curriculum.delete_subject(&1, scope: scope))
    %{ws: ws, scope: scope}
  end

  test "create then list, ordered", %{scope: scope} do
    {:ok, _} = Curriculum.create_subject(scope, %{name: "Français", position: 2})
    {:ok, _} = Curriculum.create_subject(scope, %{name: "Mathématiques", position: 1})
    assert ["Mathématiques", "Français"] = Enum.map(Curriculum.list_subjects(scope), & &1.name)
  end

  test "duplicate name is a tagged error", %{scope: scope} do
    {:ok, _} = Curriculum.create_subject(scope, %{name: "Anglais"})
    assert {:error, :duplicate_name} = Curriculum.create_subject(scope, %{name: "Anglais"})
  end

  test "name is trimmed on create and update; a padded near-duplicate is rejected", %{
    scope: scope
  } do
    # The Subject `:name` attribute trims at the type level, so create, update
    # and the seeder all store a canonical (trimmed) name — no per-caller trim.
    {:ok, s} = Curriculum.create_subject(scope, %{name: "  Allemand  "})
    assert s.name == "Allemand"

    # A padded near-duplicate collapses to the same value and hits the
    # `[:workspace_id, :name]` identity rather than slipping in as a new row.
    assert {:error, :duplicate_name} = Curriculum.create_subject(scope, %{name: " Allemand "})

    {:ok, updated} = Curriculum.update_subject(scope, s, %{name: "  Espagnol  "})
    assert updated.name == "Espagnol"
  end

  test "deactivate and delete", %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "EPS"})
    {:ok, s} = Curriculum.deactivate_subject(s, scope: scope)
    refute s.active?
    assert :ok = Curriculum.delete_subject(s, scope: scope)
    assert Curriculum.list_subjects(scope) == []
  end
end
