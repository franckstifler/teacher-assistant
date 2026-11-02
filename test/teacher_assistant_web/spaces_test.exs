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

  defp tab_labels(key, facts),
    do: for(tab <- Spaces.tab_bar(Spaces.space(key, facts)).primary, do: tab.label)

  describe "tab_bar/1 (phone navigation)" do
    test "each role space gets its four primary tabs" do
      assert tab_labels(:proviseur, facts([:head])) == [
               "Accueil",
               "Classes",
               "Élèves",
               "Bulletins"
             ]

      assert tab_labels(:censeur, facts([:vice_principal])) ==
               ["Suivi", "EDT", "Classes", "Bulletins"]

      assert tab_labels(:surveillant, facts([:discipline_master])) ==
               ["Journée", "Absences", "Élèves", "Sanctions"]

      assert tab_labels(:enseignant, facts([:teacher], teaches?: true)) ==
               ["Ma journée", "Mes cours", "Bulletins", "EDT"]
    end

    test "« Plus » holds the rest of the menu, never a primary tab" do
      %{primary: primary, more: more} = Spaces.tab_bar(Spaces.space(:proviseur, facts([:head])))
      more_paths = for s <- more, item <- s.items, do: item.path

      assert "/school/sequences" in more_paths
      assert "/school/settings" in more_paths
      refute Enum.any?(primary, &(&1.path in more_paths))
    end

    test "no two tabs open the same page" do
      for {key, roles, opts} <- [
            {:proviseur, [:head], []},
            {:censeur, [:vice_principal], []},
            {:surveillant, [:discipline_master], []},
            {:enseignant, [:teacher], [teaches?: true]}
          ] do
        paths =
          for tab <- Spaces.tab_bar(Spaces.space(key, facts(roles, opts))).primary, do: tab.path

        assert paths == Enum.uniq(paths), "#{key}: #{inspect(paths)}"
      end
    end

    test "missing chosen items are topped up from the menu" do
      # a form master who does not teach: no « Ma journée », no « Mes cours »
      assert tab_labels(:enseignant, facts([:teacher], form_master?: true)) ==
               ["Bulletins", "EDT", "Classes"]

      assert tab_labels(:intendant, facts([:bursar])) == [
               "Frais",
               "Classes",
               "Paramètres des frais"
             ]
    end
  end

  describe "owner_item/2" do
    test "is the first named item the space's menu has" do
      intendant = Spaces.space(:intendant, facts([:bursar]))
      assert Spaces.owner_item(intendant, ["fees", "classes"]).path == "/school/fees"

      teacher = Spaces.space(:enseignant, facts([:teacher], form_master?: true))
      assert Spaces.owner_item(teacher, ["fees", "classes"]).path == "/school/classes"
      assert Spaces.owner_item(teacher, ["fees"]) == nil
    end
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
    # « Photos examen » opens from Élèves, « Disponibilités » from the timetable editor
    refute "nav-school-exam-photos" in item_ids(:proviseur, facts([:head]))
    refute "nav-school-availability" in item_ids(:censeur, facts([:vice_principal]))

    for key <- [:proviseur, :censeur] do
      [_steering, school_life, organisation] =
        Spaces.space(key, facts([:head, :vice_principal])).sections

      assert school_life.label == "Scolarité"

      assert Enum.map(school_life.items, & &1.id) ==
               ["nav-school-classes", "nav-school-students", "nav-school-conduct"]

      assert organisation.label == "Organisation"

      assert Enum.map(organisation.items, & &1.id) == [
               "nav-school-timetable-editor",
               "nav-school-fees",
               "nav-school-members",
               "nav-school-settings"
             ]
    end

    # every settings page is reached from the one Paramètres entry (its hub)
    assert "nav-school-settings" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-settings" in item_ids(:censeur, facts([:vice_principal]))
    refute "nav-school-school-life" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-conduct" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-conduct" in item_ids(:censeur, facts([:vice_principal]))
    refute "nav-school-roles" in item_ids(:proviseur, facts([:head]))

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

  test "items of an off module are dropped from the menu" do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()
    op = %TeacherAssistant.Scope{current_user: TeacherFixtures.admin_user_fixture()}
    {:ok, ws} = TeacherAssistant.Organization.set_modules(op, scope.current_workspace, [:appel])

    paths =
      %{scope | current_workspace: ws}
      |> Spaces.put_space(nil)
      |> then(& &1.capabilities.space.sections)
      |> Enum.flat_map(& &1.items)
      |> Enum.map(& &1.path)

    refute "/school/bulletins" in paths
    refute "/school/sequences" in paths
    assert "/school/classes" in paths
  end
end
