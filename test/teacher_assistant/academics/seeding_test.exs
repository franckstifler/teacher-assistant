# test/teacher_assistant/academics/seeding_test.exs
defmodule TeacherAssistant.Academics.SeedingTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.Seeding
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test",
        school_type: :lycee,
        subsystem: :francophone
      })

    {:ok, year} =
      Organization.create_academic_year(school_scope(head, ws), %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{ws: ws, year: year, scope: school_scope(head, ws)}
  end

  test "seeds starter classes from the template", %{year: year, scope: scope} do
    {:ok, n} = Seeding.seed_starter_classes(scope, year)
    assert n > 0
    labels = scope |> Enrollment.list_class_groups(year) |> Enum.map(& &1.label)
    assert "6ème" in labels
    assert "2nde C" in labels
  end

  test "is idempotent once classes exist", %{ws: _ws, year: year, scope: scope} do
    {:ok, _} = Seeding.seed_starter_classes(scope, year)
    assert {:ok, 0} = Seeding.seed_starter_classes(scope, year)
  end
end
