defmodule TeacherAssistantWeb.SpacesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistantWeb.Spaces

  defp facts(roles, opts \\ []),
    do: %{
      roles: roles,
      teaches?: Keyword.get(opts, :teaches?, false),
      form_master?: Keyword.get(opts, :form_master?, false),
      pending_corrections: Keyword.get(opts, :pending_corrections, 0),
      decided_corrections: Keyword.get(opts, :decided_corrections, 0)
    }

  defp item_ids(key, facts),
    do: for(section <- Spaces.space(key, facts).sections, item <- section.items, do: item.id)

  test "spaces follow the roles, in priority order" do
    assert Spaces.keys_for(facts([:head])) == [:proviseur]

    assert Spaces.keys_for(facts([:teacher, :vice_principal], teaches?: true)) == [
             :censeur,
             :enseignant
           ]

    assert Spaces.keys_for(facts([:discipline_master, :bursar])) == [:surveillant, :intendant]
    assert Spaces.keys_for(facts([:teacher], teaches?: true)) == [:enseignant]
  end

  test "a member with no role-specific space who does not teach gets École" do
    assert Spaces.keys_for(facts([:hod])) == [:ecole]
    assert Spaces.keys_for(facts([:librarian])) == [:ecole]
    assert Spaces.keys_for(facts([:teacher])) == [:ecole]
    assert Spaces.keys_for(facts([:teacher], form_master?: true)) == [:enseignant]
  end

  test "resolve keeps an allowed stored space and falls back otherwise" do
    assert Spaces.resolve([:censeur, :enseignant], :enseignant) == :enseignant
    assert Spaces.resolve([:censeur, :enseignant], :proviseur) == :censeur
    assert Spaces.resolve([:enseignant], nil) == :enseignant
  end

  test "space keys are parsed from a closed list" do
    assert Spaces.parse_key("censeur") == :censeur
    assert Spaces.parse_key("admin") == nil
  end

  test "homes and menus" do
    assert Spaces.space(:proviseur, facts([:head])).home == "/school"
    assert Spaces.space(:censeur, facts([:vice_principal])).home == "/school/sequences"
    assert Spaces.space(:surveillant, facts([:discipline_master])).home == "/school/day"
    assert Spaces.space(:enseignant, facts([:teacher], teaches?: true)).home == "/school/today"
    assert Spaces.space(:ecole, facts([:hod])).home == "/school/classes"

    assert "nav-school-members" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-members" in item_ids(:censeur, facts([:vice_principal]))
    refute "nav-school-periods" in item_ids(:censeur, facts([:vice_principal]))

    assert [%{items: [%{id: "nav-school-sequences", path: "/school/sequences"} | _]} | _] =
             Spaces.space(:censeur, facts([:vice_principal])).sections

    assert ["nav-school-dashboard", "nav-school-sequences" | _] =
             item_ids(:proviseur, facts([:head]))

    assert item_ids(:surveillant, facts([:discipline_master])) ==
             [
               "nav-school-day",
               "nav-school-absences",
               "nav-school-conduct",
               "nav-school-sanctions",
               "nav-school-classes",
               "nav-school-students",
               "nav-school-school-life"
             ]

    assert "nav-school-students" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-students" in item_ids(:censeur, facts([:vice_principal]))
    assert "nav-school-school-life" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-school-life" in item_ids(:censeur, facts([:vice_principal]))
    assert "nav-school-conduct" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-conduct" in item_ids(:censeur, facts([:vice_principal]))
    assert "nav-school-roles" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-roles" in item_ids(:censeur, facts([:vice_principal]))

    refute "nav-school-sequences" in item_ids(:enseignant, facts([:teacher], teaches?: true))

    assert item_ids(:enseignant, facts([:teacher], teaches?: true)) == [
             "nav-school-today",
             "nav-school-courses",
             "nav-school-bulletins",
             "nav-school-timetable-me",
             "nav-school-corrections"
           ]

    assert item_ids(:enseignant, facts([:teacher], teaches?: true, form_master?: true)) ==
             [
               "nav-school-today",
               "nav-school-courses",
               "nav-school-classes",
               "nav-school-bulletins",
               "nav-school-timetable-me",
               "nav-school-corrections"
             ]

    assert item_ids(:enseignant, facts([:teacher], form_master?: true)) ==
             ["nav-school-classes", "nav-school-bulletins", "nav-school-timetable-me"]
  end

  defp item(key, facts, id),
    do:
      Enum.find_value(Spaces.space(key, facts).sections, fn section ->
        Enum.find(section.items, &(&1.id == id)) &&
          {section.label, Enum.find(section.items, &(&1.id == id))}
      end)

  test "corrections of marks: teachers under Démarches, admins with the pending count" do
    assert {"Démarches", %{badge: 2}} =
             item(
               :enseignant,
               facts([:teacher], teaches?: true, decided_corrections: 2),
               "nav-school-corrections"
             )

    for key <- [:proviseur, :censeur] do
      assert {_, %{badge: 3, path: "/school/corrections/review"}} =
               item(key, facts([:head], pending_corrections: 3), "nav-school-correction-review")
    end

    refute item(:surveillant, facts([:discipline_master]), "nav-school-correction-review")
  end
end

defmodule TeacherAssistantWeb.SpacesCountsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, TeacherFixtures}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Spaces

  test "the Absences badge is the count of absences to justify, as before" do
    %{scope: scope, year: year, head_user: head} = TeacherFixtures.setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bello", sex: :m})
    [a, b] = scope |> Enrollment.list_roster(cg) |> Enum.map(& &1.enrollment)
    :ok = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    today = Reference.today()

    for p <- [p1, p2],
        do:
          {:ok, _} =
            Attendance.record_period(scope, cg, p, tc, today, [{a.id, :absent}, {b.id, :absent}])

    {:ok, _} = Attendance.justify_day(scope, b, today, :maladie)

    # the figure the badge was computed with before `absences_to_justify/2`
    {first, last} = Attendance.current_sequence_range(scope, today)

    before =
      scope |> Attendance.absence_days(first, last, today) |> Enum.count(&(not &1.justified?))

    assert before == 1
    assert Spaces.counts(:surveillant, scope).unjustified_absences == before
    assert Attendance.absences_to_justify(scope, today).count == before
  end
end
