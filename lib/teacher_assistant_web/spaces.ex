defmodule TeacherAssistantWeb.Spaces do
  @moduledoc """
  Role spaces (spec E): what each school member sees in the menu and where they land.
  A space is data — label, home, menu sections. This never grants anything: every
  screen keeps its own policy checks, and a link missing from a menu stays refused
  when typed directly.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Academics.Reference

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
  """
  def put_space(%{current_workspace: %{}} = scope, stored) do
    facts = facts(scope)
    keys = keys_for(facts)
    key = resolve(keys, parse_key(stored))
    space = space(key, Map.merge(facts, counts(key, scope)))

    %{scope | capabilities: Map.merge(scope.capabilities || %{}, %{spaces: keys, space: space})}
  end

  def put_space(scope, _stored), do: scope

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
        if(Assessment.can_decide_corrections?(scope),
          do: Assessment.pending_corrections_count(scope),
          else: 0
        ),
      decided_corrections: if(teaches?, do: Assessment.unseen_decisions_count(scope), else: 0)
    }
  end

  @doc """
  The menu counts of the space `key` (mockup badges), computed only for the space
  shown: late teachers on "Suivi des séquences", missed roll calls on "Aujourd'hui"
  and "Ma journée", unjustified absences on "Absences".
  """
  def counts(key, %{current_academic_year: %{} = year} = scope)
      when key in [:proviseur, :censeur] do
    case Assessment.default_sequence(Organization.list_sequences(scope, year), Reference.today()) do
      nil -> %{}
      seq -> %{late_teachers: Assessment.sequence_entry_grid(scope, year, seq).late_teacher_count}
    end
  end

  def counts(:surveillant, scope) do
    today = Reference.today()

    unjustified =
      case Attendance.current_sequence_range(scope, today) do
        nil ->
          0

        {first, last} ->
          scope |> Attendance.absence_days(first, last, today) |> Enum.count(&(not &1.justified?))
      end

    %{
      missed_calls: length(Attendance.school_day(scope, today, Reference.now()).missed),
      unjustified_absences: unjustified
    }
  end

  def counts(:enseignant, %{current_user: user} = scope) do
    calls =
      scope
      |> Attendance.teacher_day(user, Reference.today(), Reference.now())
      |> Enum.count(&(&1.status in [:in_progress, :missed]))

    %{calls_to_do: calls}
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
          classes(),
          students(),
          timetable_editor(),
          members(),
          correction_review(facts.pending_corrections)
        ]),
        section(gettext("Paramètres"), [
          settings(),
          coefficients(),
          evaluations(),
          appreciations(),
          passage(),
          bulletin_template(),
          holidays(),
          assignments(),
          periods()
        ])
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
          classes(),
          students(),
          timetable_editor(),
          members(),
          correction_review(facts.pending_corrections)
        ]),
        section(gettext("Paramètres"), [
          settings(),
          coefficients(),
          evaluations(),
          appreciations(),
          passage(),
          bulletin_template(),
          holidays(),
          assignments()
        ])
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
          classes(),
          students()
        ])
      ]
    }
  end

  def space(:intendant, _facts) do
    %{
      key: :intendant,
      label: label(:intendant),
      home: ~p"/school/classes",
      sections: [section(gettext("Intendance"), [classes()])]
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
        gettext("Corrections de notes"),
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

  defp members, do: item("members", gettext("Members"), "hero-user-group", ~p"/school/members")

  defp settings,
    do: item("settings", gettext("Settings"), "hero-cog-6-tooth", ~p"/school/settings")

  defp coefficients,
    do:
      item(
        "coefficients",
        gettext("Matières & coefficients"),
        "hero-table-cells",
        ~p"/school/settings/coefficients"
      )

  defp evaluations,
    do:
      item(
        "evaluations",
        gettext("Évaluations & moyennes"),
        "hero-calculator",
        ~p"/school/settings/evaluations"
      )

  defp appreciations,
    do:
      item(
        "appreciations",
        gettext("Appréciations & distinctions"),
        "hero-academic-cap",
        ~p"/school/settings/appreciations"
      )

  defp passage,
    do:
      item(
        "passage",
        gettext("Passage & redoublement"),
        "hero-arrow-trending-up",
        ~p"/school/settings/passage"
      )

  defp bulletin_template,
    do:
      item(
        "bulletin_template",
        gettext("Modèle de bulletin"),
        "hero-document-duplicate",
        ~p"/school/settings/bulletin"
      )

  defp holidays,
    do:
      item(
        "holidays",
        gettext("Congés & jours fériés"),
        "hero-calendar",
        ~p"/school/settings/holidays"
      )

  defp assignments,
    do:
      item(
        "assignments",
        gettext("Affectations"),
        "hero-squares-2x2",
        ~p"/school/settings/assignments"
      )

  defp timetable_editor,
    do:
      item(
        "timetable-editor",
        gettext("Emploi du temps"),
        "hero-table-cells",
        ~p"/school/timetable"
      )

  defp councils,
    do: item("councils", gettext("Conseils de classe"), "hero-user-group", ~p"/school/councils")

  defp bulletins,
    do: item("bulletins", gettext("Bulletins"), "hero-document-text", ~p"/school/bulletins")

  defp periods, do: item("periods", gettext("Horaires"), "hero-clock", ~p"/school/periods")
end
