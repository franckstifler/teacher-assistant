defmodule TeacherAssistantWeb.Spaces do
  @moduledoc """
  Role spaces (spec E): what each school member sees in the menu and where they land.
  A space is data — label, home, menu sections. This never grants anything: every
  screen keeps its own policy checks, and a link missing from a menu stays refused
  when typed directly.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{Curriculum, Enrollment}

  @order [:proviseur, :censeur, :surveillant, :intendant, :enseignant, :ecole]
  @by_role %{head: :proviseur, vice_principal: :censeur, discipline_master: :surveillant, bursar: :intendant}
  @by_param Map.new(@order, &{Atom.to_string(&1), &1})

  @doc "The member's spaces, in priority order (never empty)."
  def keys_for(%{roles: roles, teaches?: teaches?, form_master?: form_master?}) do
    keys = MapSet.new(for role <- roles, key = @by_role[role], key != nil, do: key)
    keys = if teaches? or form_master?, do: MapSet.put(keys, :enseignant), else: keys

    case Enum.filter(@order, &MapSet.member?(keys, &1)) do
      [] -> [:ecole]
      ordered -> ordered
    end
  end

  @doc "The stored space when it is still one of the member's, otherwise their first."
  def resolve([first | _] = keys, stored), do: if(stored in keys, do: stored, else: first)

  def parse_key(param) when is_binary(param), do: Map.get(@by_param, param)
  def parse_key(_), do: nil

  @doc "What the space-deciding facts are for a school scope (DB reads, once per mount)."
  def facts(%{current_workspace: %{}} = scope) do
    year = scope.current_academic_year

    %{
      roles: scope.current_roles || [],
      teaches?: Curriculum.list_units_for_scope(scope) != [],
      form_master?: year != nil and Enrollment.list_form_master_classes(scope, year) != []
    }
  end

  def space(:proviseur, _facts) do
    %{
      key: :proviseur,
      label: gettext("Proviseur"),
      home: ~p"/school",
      sections: [
        section(gettext("Pilotage"), [dashboard(), classes(), members()]),
        section(gettext("Paramètres"), [settings(), coefficients(), evaluations(), periods()])
      ]
    }
  end

  def space(:censeur, _facts) do
    %{
      key: :censeur,
      label: gettext("Censeur"),
      home: ~p"/school",
      sections: [
        section(gettext("Suivi pédagogique"), [dashboard(), classes(), members()]),
        section(gettext("Paramètres"), [settings(), coefficients(), evaluations()])
      ]
    }
  end

  def space(:surveillant, _facts) do
    %{
      key: :surveillant,
      label: gettext("Surveillant général"),
      home: ~p"/school/classes",
      sections: [section(gettext("Vie scolaire"), [classes()])]
    }
  end

  def space(:intendant, _facts) do
    %{
      key: :intendant,
      label: gettext("Intendant"),
      home: ~p"/school/classes",
      sections: [section(gettext("Intendance"), [classes()])]
    }
  end

  def space(:enseignant, facts) do
    items =
      [facts.teaches? && courses(), facts.form_master? && classes(), timetable()]
      |> Enum.filter(& &1)

    %{
      key: :enseignant,
      label: gettext("Enseignant"),
      home: if(facts.teaches?, do: ~p"/school/courses", else: ~p"/school/classes"),
      sections: [section(gettext("Enseignement"), items)]
    }
  end

  def space(:ecole, _facts) do
    %{
      key: :ecole,
      label: gettext("École"),
      home: ~p"/school/classes",
      sections: [section(gettext("École"), [classes(), timetable()])]
    }
  end

  defp section(label, items), do: %{label: label, items: items}

  defp item(id, label, icon, path), do: %{id: "nav-school-#{id}", label: label, icon: icon, path: path}

  defp dashboard, do: item("dashboard", gettext("Dashboard"), "hero-squares-2x2", ~p"/school")
  defp courses, do: item("courses", gettext("Mes cours"), "hero-academic-cap", ~p"/school/courses")
  defp classes, do: item("classes", gettext("Classes"), "hero-rectangle-group", ~p"/school/classes")

  defp timetable,
    do: item("timetable-me", gettext("Mon emploi du temps"), "hero-calendar-days", ~p"/school/timetable/me")

  defp members, do: item("members", gettext("Members"), "hero-user-group", ~p"/school/members")
  defp settings, do: item("settings", gettext("Settings"), "hero-cog-6-tooth", ~p"/school/settings")

  defp coefficients,
    do: item("coefficients", gettext("Matières & coefficients"), "hero-table-cells", ~p"/school/settings/coefficients")

  defp evaluations,
    do: item("evaluations", gettext("Évaluations & moyennes"), "hero-calculator", ~p"/school/settings/evaluations")

  defp periods, do: item("periods", gettext("Périodes"), "hero-clock", ~p"/school/periods")
end
