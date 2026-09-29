defmodule TeacherAssistantWeb.SpacesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistantWeb.Spaces

  defp facts(roles, opts \\ []),
    do: %{roles: roles, teaches?: Keyword.get(opts, :teaches?, false), form_master?: Keyword.get(opts, :form_master?, false)}

  defp item_ids(key, facts),
    do: for(section <- Spaces.space(key, facts).sections, item <- section.items, do: item.id)

  test "spaces follow the roles, in priority order" do
    assert Spaces.keys_for(facts([:head])) == [:proviseur]
    assert Spaces.keys_for(facts([:teacher, :vice_principal], teaches?: true)) == [:censeur, :enseignant]
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
    assert Spaces.space(:surveillant, facts([:discipline_master])).home == "/school/classes"
    assert Spaces.space(:enseignant, facts([:teacher], teaches?: true)).home == "/school/courses"
    assert Spaces.space(:ecole, facts([:hod])).home == "/school/classes"

    assert "nav-school-members" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-members" in item_ids(:censeur, facts([:vice_principal]))
    refute "nav-school-periods" in item_ids(:censeur, facts([:vice_principal]))

    assert item_ids(:enseignant, facts([:teacher], teaches?: true)) == [
             "nav-school-courses",
             "nav-school-timetable-me"
           ]

    assert item_ids(:enseignant, facts([:teacher], teaches?: true, form_master?: true)) ==
             ["nav-school-courses", "nav-school-classes", "nav-school-timetable-me"]
  end
end
