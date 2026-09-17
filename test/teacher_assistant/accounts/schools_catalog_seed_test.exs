defmodule TeacherAssistant.Accounts.SchoolsCatalogSeedTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.Academics.Subjects
  alias TeacherAssistant.TeacherFixtures

  test "creating a school seeds its subject catalog from the template" do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test", school_type: :lycee, subsystem: :francophone})

    names = ws |> Subjects.list() |> Enum.map(& &1.name)
    assert "Mathématiques" in names
    assert "Français" in names
    assert length(names) >= 10
  end

  test "a technical school seeds technical subjects too" do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "CETIC Test", school_type: :cetic, subsystem: :francophone})
    names = ws |> Subjects.list() |> Enum.map(& &1.name)
    assert "Atelier / Pratique" in names
  end
end
