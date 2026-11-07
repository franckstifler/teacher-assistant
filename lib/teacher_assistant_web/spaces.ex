defmodule TeacherAssistantWeb.Spaces do
  @moduledoc """
  Role spaces (spec E): what each school member sees in the menu and where they land.
  A space is data — label, home, menu sections. This never grants anything: every
  screen keeps its own policy checks, and a link missing from a menu stays refused
  when typed directly.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{
    Assessment,
    Attendance,
    Curriculum,
    Discipline,
    Enrollment,
    Organization
  }

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.{Modules, Scope}

  @order [:proviseur, :censeur, :surveillant, :intendant, :enseignant, :ecole]
  @by_role %{
    head: :proviseur,
    vice_principal: :censeur,
    discipline_master: :surveillant,
    bursar: :intendant
  }
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

  @doc """
  The school scope with the member's spaces and the current one (`stored`, the
  session value, when still theirs) in its capabilities. Navigation only.

  `counts?: false` leaves out the menu badges (`counts/2`), which can read a whole
  séquence of marks: for requests that draw no menu (photos, logos, prints) and
  for a LiveView's first, not-yet-connected render.
  """
  def put_space(scope, stored, opts \\ [])

  def put_space(%{current_workspace: %{}} = scope, stored, opts) do
    facts = facts(scope)
    keys = keys_for(facts)
    key = resolve(keys, parse_key(stored))
    counts = if Keyword.get(opts, :counts?, true), do: counts(key, scope), else: %{}

    space =
      key
      |> space(Map.merge(facts, counts))
      |> drop_off_modules(scope)

    %{scope | capabilities: Map.merge(scope.capabilities || %{}, %{spaces: keys, space: space})}
  end

  def put_space(scope, _stored, _opts), do: scope

  @doc """
  Whether `path` leads to a screen the scope's school has: core, or a module it has
  (operator console spec §1). Paths that are not routes count as allowed.
  """
  def path_allowed?(scope, path) do
    case Phoenix.Router.route_info(TeacherAssistantWeb.Router, "GET", path, "") do
      %{phoenix_live_view: {view, _action, _opts, _extra}} ->
        allowed?(scope, Modules.module_for_view(view))

      %{plug: controller, plug_opts: action} ->
        allowed?(scope, Modules.module_for_controller(controller, action))

      :error ->
        true
    end
  end

  defp allowed?(_scope, key) when key in [nil, :core], do: true
  defp allowed?(scope, key), do: Scope.module?(scope, key)

  # Menu items of modules the school does not have go; a home among them falls back to
  # the class list, which every space can open.
  defp drop_off_modules(space, scope) do
    sections =
      space.sections
      |> Enum.map(fn s -> %{s | items: Enum.filter(s.items, &path_allowed?(scope, &1.path))} end)
      |> Enum.reject(&(&1.items == []))

    home = if path_allowed?(scope, space.home), do: space.home, else: ~p"/school/classes"
    %{space | sections: sections, home: home}
  end

  @doc "What the space-deciding facts are for a school scope (DB reads, once per mount)."
  def facts(%{current_workspace: %{}} = scope) do
    year = scope.current_academic_year
    teaches? = Curriculum.list_units_for_scope(scope) != []

    %{
      roles: scope.current_roles || [],
      teaches?: teaches?,
      form_master?: year != nil and Enrollment.list_form_master_classes(scope, year) != [],
      # Menu badges (spec D3c), counted only for whom the item shows.
      pending_corrections:
        if(Scope.module?(scope, :notes) and Assessment.can_decide_corrections?(scope),
          do: Assessment.pending_corrections_count(scope),
          else: 0
        ),
      decided_corrections:
        if(teaches? and Scope.module?(scope, :notes),
          do: Assessment.unseen_decisions_count(scope),
          else: 0
        )
    }
  end

  @doc """
  The menu counts of the space `key` (mockup badges), computed only for the space
  shown: late teachers on "Suivi des séquences", missed roll calls on "Aujourd'hui"
  and "Ma journée", unjustified absences on "Absences".
  """
  # Badges are counted only for the modules the school has (operator console spec §1).
  def counts(key, %{current_academic_year: %{} = year} = scope)
      when key in [:proviseur, :censeur] do
    with true <- Scope.module?(scope, :notes),
         %{} = seq <-
           Assessment.default_sequence(
             Organization.list_sequences(scope, year),
             Reference.today()
           ) do
      %{late_teachers: Assessment.sequence_entry_grid(scope, year, seq).late_teacher_count}
    else
      _ -> %{}
    end
  end

  def counts(:surveillant, scope) do
    today = Reference.today()
    appel? = Scope.module?(scope, :appel)

    %{
      missed_calls:
        if(appel?, do: length(Attendance.school_day(scope, today, Reference.now()).missed)),
      unjustified_absences: if(appel?, do: Attendance.absences_to_justify(scope, today).count),
      parents_to_notify:
        case {Scope.module?(scope, :discipline), scope.current_academic_year} do
          {true, %{} = year} -> Discipline.count_parents_to_notify(scope, year)
          _ -> nil
        end
    }
  end

  def counts(:enseignant, %{current_user: user} = scope) do
    if Scope.module?(scope, :appel) do
      calls =
        scope
        |> Attendance.teacher_day(user, Reference.today(), Reference.now())
        |> Enum.count(&(&1.status in [:in_progress, :missed]))

      %{calls_to_do: calls}
    else
      %{}
    end
  end

  def counts(_key, _scope), do: %{}

  def label(:proviseur), do: gettext("Proviseur")
  def label(:censeur), do: gettext("Censeur")
  def label(:surveillant), do: gettext("Surveillant général")
  def label(:intendant), do: gettext("Intendant")
  def label(:enseignant), do: gettext("Enseignant")
  def label(:ecole), do: gettext("École")

  def space(:proviseur, facts) do
    %{
      key: :proviseur,
      label: label(:proviseur),
      home: ~p"/school",
      sections: [
        section(gettext("Pilotage"), [
          dashboard(),
          sequences(facts[:late_teachers]),
          bulletins(),
          councils(),
          correction_review(facts.pending_corrections)
        ]),
        section(gettext("Scolarité"), [classes(), students(), conduct()]),
        # one settings entry: the hub links to every settings page
        section(gettext("Organisation"), [timetable_editor(), fees(), members(), settings()])
      ]
    }
  end

  def space(:censeur, facts) do
    %{
      key: :censeur,
      label: label(:censeur),
      home: ~p"/school/sequences",
      sections: [
        section(gettext("Suivi pédagogique"), [
          sequences(facts[:late_teachers]),
          bulletins(),
          councils(),
          correction_review(facts.pending_corrections)
        ]),
        section(gettext("Scolarité"), [classes(), students(), conduct()]),
        # « Disponibilités » opens from the timetable editor
        section(gettext("Organisation"), [timetable_editor(), fees(), members(), settings()])
      ]
    }
  end

  def space(:surveillant, facts) do
    %{
      key: :surveillant,
      label: label(:surveillant),
      home: ~p"/school/day",
      sections: [
        section(gettext("Vie scolaire"), [
          school_day(facts[:missed_calls]),
          absences(facts[:unjustified_absences]),
          conduct(),
          sanctions(facts[:parents_to_notify]),
          classes(),
          students(),
          school_life_settings()
        ])
      ]
    }
  end

  def space(:intendant, _facts) do
    %{
      key: :intendant,
      label: label(:intendant),
      home: ~p"/school/fees",
      sections: [section(gettext("Intendance"), [fees(), classes(), fee_settings()])]
    }
  end

  def space(:enseignant, facts) do
    items =
      [
        facts.teaches? && my_day(facts[:calls_to_do]),
        facts.teaches? && courses(),
        facts.form_master? && classes(),
        (facts.teaches? or facts.form_master?) && bulletins(),
        timetable()
      ]
      |> Enum.filter(& &1)

    %{
      key: :enseignant,
      label: label(:enseignant),
      home: if(facts.teaches?, do: ~p"/school/today", else: ~p"/school/classes"),
      sections:
        [
          section(gettext("Enseignement"), items),
          facts.teaches? &&
            section(gettext("Démarches"), [corrections(facts.decided_corrections)])
        ]
        |> Enum.filter(& &1)
    }
  end

  def space(:ecole, _facts) do
    %{
      key: :ecole,
      label: label(:ecole),
      home: ~p"/school/classes",
      sections: [section(gettext("École"), [classes(), timetable()])]
    }
  end

  @doc """
  The phone tab bar of a space (UI review 2026-10): up to four `primary` tabs,
  each an item of the space's menu under its short tab label, and the menu `more`
  sections minus those items (the « Plus » sheet). A space whose chosen items
  are missing (a member who does not teach, a school without a module…) is
  topped up from its menu in order, under short labels too.
  """
  def tab_bar(%{key: key, sections: sections}) do
    items = Enum.flat_map(sections, & &1.items)
    by_id = Map.new(items, &{&1.id, &1})

    chosen = for id <- tab_spec(key), item = by_id["nav-school-" <> id], item != nil, do: item
    taken = MapSet.new(chosen, & &1.id)

    primary =
      (chosen ++ Enum.reject(items, &MapSet.member?(taken, &1.id)))
      |> Enum.take(4)
      |> Enum.map(&%{&1 | label: tab_label(&1)})

    shown = MapSet.new(primary, & &1.id)

    more =
      sections
      |> Enum.map(fn s -> %{s | items: Enum.reject(s.items, &MapSet.member?(shown, &1.id))} end)
      |> Enum.reject(&(&1.items == []))

    %{primary: primary, more: more}
  end

  @doc """
  The first of `ids` (« fees », « classes »…) that the space's menu has, as its
  item: the entry a page belongs to, whatever its path. Nil when none is there.
  """
  def owner_item(%{sections: sections}, ids) do
    items = Enum.flat_map(sections, & &1.items)

    Enum.find_value(ids, fn id ->
      Enum.find(items, &(&1.id == "nav-school-" <> id))
    end)
  end

  # A page under an entry keeps it lit (a class under Classes, every settings page
  # under Paramètres). "/school" (the dashboard) only matches itself.
  @settings_pages ["/school/settings", "/school/periods", "/school/years"]

  @doc "Whether `path` is the menu entry `href`'s page or one under it."
  def path_under_item?(nil, _href), do: false
  def path_under_item?(path, href) when path == href, do: true
  def path_under_item?(_path, "/school"), do: false

  def path_under_item?(path, "/school/settings"),
    do: Enum.any?(@settings_pages, &(path == &1 or String.starts_with?(path, &1 <> "/")))

  # « Mon emploi du temps » is the teacher's own item, not the editor's; « Disponibilités »
  # names the editor as its entry (`nav`).
  def path_under_item?(_path, "/school/timetable"), do: false

  def path_under_item?(path, href), do: String.starts_with?(path, href <> "/")

  @doc "Whether the space's menu has an entry for `path` (it or a page under it)."
  def in_menu?(%{sections: sections}, path) when is_binary(path),
    do: Enum.any?(sections, fn s -> Enum.any?(s.items, &path_under_item?(path, &1.path)) end)

  def in_menu?(_space, _path), do: false

  @doc "`owner_item/2` for the scope's current space (nil outside a school)."
  def owner_item_for(%{capabilities: %{space: %{} = space}}, ids), do: owner_item(space, ids)
  def owner_item_for(_scope, _ids), do: nil

  defp tab_spec(:proviseur), do: ["dashboard", "classes", "students", "bulletins"]
  defp tab_spec(:censeur), do: ["sequences", "timetable-editor", "classes", "bulletins"]
  defp tab_spec(:surveillant), do: ["day", "absences", "students", "sanctions"]

  # Marks are entered per course, so « Mes cours » covers them (a course's pages
  # name it as their menu entry); Bulletins gets the third tab.
  defp tab_spec(:enseignant), do: ["today", "courses", "bulletins", "timetable-me"]
  defp tab_spec(_key), do: []

  # A tab is a fifth of a phone's width: menu labels longer than a word get a
  # short one, for chosen tabs and topped-up ones alike.
  defp tab_label(%{id: "nav-school-" <> id} = item) do
    case id do
      "dashboard" -> gettext("Accueil")
      "sequences" -> gettext("Suivi")
      "timetable-editor" -> gettext("EDT")
      "timetable-me" -> gettext("EDT")
      "day" -> gettext("Journée")
      "corrections" -> gettext("Corrections")
      "correction-review" -> gettext("Validations")
      "councils" -> gettext("Conseils")
      "settings" -> gettext("Paramètres")
      "fee-settings" -> gettext("Paramètres")
      "school-life" -> gettext("Règles")
      _ -> item.label
    end
  end

  defp section(label, items), do: %{label: label, items: items}

  defp item(id, label, icon, path, badge \\ nil, badge_tone \\ :warning),
    do: %{
      id: "nav-school-#{id}",
      label: label,
      icon: icon,
      path: path,
      badge: badge,
      badge_tone: badge_tone
    }

  defp corrections(decided),
    do:
      item(
        "corrections",
        gettext("Corrections de notes"),
        "hero-pencil-square",
        ~p"/school/corrections",
        decided
      )

  defp correction_review(pending),
    do:
      item(
        "correction-review",
        gettext("Validation des corrections"),
        "hero-shield-check",
        ~p"/school/corrections/review",
        pending
      )

  defp dashboard, do: item("dashboard", gettext("Dashboard"), "hero-squares-2x2", ~p"/school")

  defp sequences(late),
    do:
      item(
        "sequences",
        gettext("Suivi des séquences"),
        "hero-chart-bar-square",
        ~p"/school/sequences",
        late,
        :error
      )

  defp my_day(to_do),
    do: item("today", gettext("Ma journée"), "hero-sun", ~p"/school/today", to_do)

  defp school_day(missed),
    do:
      item(
        "day",
        gettext("Aujourd'hui"),
        "hero-clipboard-document-check",
        ~p"/school/day",
        missed,
        :error
      )

  defp absences(unjustified),
    do:
      item(
        "absences",
        gettext("Absences"),
        "hero-user-minus",
        ~p"/school/absences",
        unjustified
      )

  defp sanctions(to_notify),
    do: item("sanctions", gettext("Sanctions"), "hero-flag", ~p"/school/sanctions", to_notify)

  defp conduct,
    do: item("conduct", gettext("Conduite"), "hero-hand-thumb-up", ~p"/school/conduct")

  defp courses,
    do: item("courses", gettext("Mes cours"), "hero-academic-cap", ~p"/school/courses")

  defp classes,
    do: item("classes", gettext("Classes"), "hero-rectangle-group", ~p"/school/classes")

  defp students,
    do: item("students", gettext("Élèves"), "hero-identification", ~p"/school/students")

  defp timetable,
    do:
      item(
        "timetable-me",
        gettext("Mon emploi du temps"),
        "hero-calendar-days",
        ~p"/school/timetable/me"
      )

  defp members, do: item("members", gettext("Members"), "hero-users", ~p"/school/members")

  defp settings,
    do: item("settings", gettext("Settings"), "hero-cog-6-tooth", ~p"/school/settings")

  defp school_life_settings,
    do:
      item(
        "school-life",
        gettext("Assiduité & discipline"),
        "hero-scale",
        ~p"/school/settings/school-life"
      )

  defp timetable_editor,
    do:
      item(
        "timetable-editor",
        gettext("Emploi du temps"),
        "hero-table-cells",
        ~p"/school/timetable"
      )

  defp fees, do: item("fees", gettext("Frais"), "hero-banknotes", ~p"/school/fees")

  defp fee_settings,
    do:
      item(
        "fee-settings",
        gettext("Paramètres des frais"),
        "hero-adjustments-horizontal",
        ~p"/school/settings/fees"
      )

  defp councils,
    do: item("councils", gettext("Conseils de classe"), "hero-user-group", ~p"/school/councils")

  defp bulletins,
    do: item("bulletins", gettext("Bulletins"), "hero-document-text", ~p"/school/bulletins")
end
