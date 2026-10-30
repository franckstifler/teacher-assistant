defmodule TeacherAssistant.ReportCards do
  @moduledoc """
  Report-card publication (spec I2). A class's trimester or annual report cards are a
  draft (live figures) until the Proviseur or Censeur publishes them; publishing stores
  `live_view/3` as a snapshot, which every screen then renders instead of live figures.
  Séquence report cards are always live. `view_for/3` decides what a user may see:
  class managers see drafts and publications, teachers of the class publications only.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext
  require Ash.Query
  require Logger

  alias TeacherAssistant.{
    Accounts,
    Assessment,
    Attendance,
    Curriculum,
    Discipline,
    Enrollment,
    Notifications,
    Organization
  }

  alias TeacherAssistant.Councils

  alias TeacherAssistant.Accounts.Checks

  alias TeacherAssistant.Academics.{
    AcademicYear,
    BulletinPublication,
    BulletinLayout,
    BulletinTemplate,
    ClassGroup,
    EntryProgress,
    Reference,
    Sequence,
    Term
  }

  alias TeacherAssistant.Scope

  @doc "What the report card, class results and print render, computed now."
  def live_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    fm = Enrollment.form_master(scope, cg)
    results = Assessment.class_results_for_period(scope, cg, period)
    template = template(scope, cg)
    roster = Enrollment.list_roster(scope, cg)
    guardians = Enrollment.guardians_for_students(scope, Enum.map(roster, & &1.student.id))

    %{
      results: results,
      council: council_entry(scope, cg, period, results),
      roster: Enum.map(roster, &plain_entry(&1, guardians)),
      # Spec bulletin v2: snapshots published before these keys read them with `Map.get`.
      competences: competences(scope, cg, period),
      sequences_per_term: sequences_per_term(period),
      prior_terms: prior_terms(scope, cg, period, template),
      annual: annual_summary(scope, cg, period, template),
      conduct: Attendance.bulletin_conduct(scope, cg, period),
      discipline:
        scope
        |> Discipline.class_discipline(cg, period)
        |> Map.new(fn {id, summary} -> {id, plain_discipline(summary)} end),
      form_master:
        fm && %{name: fm.name, email: fm.email && to_string(fm.email), phone: fm.phone},
      group_subtotals?: group_subtotals?(scope),
      template: template,
      teachers: teachers(scope, cg)
    }
  end

  # Each subject's teacher by teaching context (the class's own contexts, which the
  # subject rows carry; combined-course members are the class's contexts too).
  # Snapshots published before this key read it with `Map.get(view, :teachers, %{})`.
  defp teachers(scope, cg) do
    scope
    |> Curriculum.list_assignments_for_class(cg)
    |> Map.new(&{&1.id, Accounts.User.display_name(&1.teacher)})
  end

  @doc "The class's printed-card template under the school's current settings (spec I5)."
  def template(%Scope{} = scope, %ClassGroup{} = cg) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)

    template =
      BulletinTemplate.resolve(
        profile,
        scope.current_workspace.name,
        cg,
        head_name(scope, profile)
      )

    # Operator console spec §1: no absences without roll call, no conduct without discipline.
    hidden =
      [absences: :appel, conduct: :discipline]
      |> Enum.reject(fn {_element, module} -> Scope.module?(scope, module) end)
      |> Enum.map(&elem(&1, 0))

    %{template | elements: template.elements -- hidden}
  end

  @doc """
  Spec bulletin v2 §7: the head's printed name — the profile's `head_name` when set,
  else the first active member holding the head role.
  """
  def head_name(%Scope{} = scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> head_name(scope, profile)
      _ -> head_member_name(scope)
    end
  end

  defp head_name(_scope, %{head_name: name}) when is_binary(name) and name != "", do: name
  defp head_name(scope, _profile), do: head_member_name(scope)

  defp head_member_name(scope) do
    scope
    |> Accounts.list_members()
    |> Enum.find(&(:head in &1.roles))
    |> case do
      %{user: %Accounts.User{} = user} -> Accounts.User.display_name(user)
      _ -> nil
    end
  end

  @doc "The template a view renders with: its own (drafts, v3 snapshots), else the current settings."
  def template_of(%Scope{} = scope, %ClassGroup{} = cg, view),
    do: Map.get(view, :template) || template(scope, cg)

  @doc "The published snapshot when there is one, else the live draft."
  def class_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    case current_publication(scope, cg, period) do
      nil -> {:draft, live_view(scope, cg, period)}
      pub -> {:published, pub, pub.snapshot}
    end
  end

  @doc "The publication in force for the class and period, or nil (always nil for a séquence)."
  def current_publication(_scope, _cg, {:sequence, _}), do: nil

  def current_publication(%Scope{} = scope, %ClassGroup{} = cg, period),
    do: scope |> history(cg, period) |> Enum.find(&(&1.status == :published))

  @doc "Every publication of the class for the period, newest first."
  def history(_scope, _cg, {:sequence, _}), do: []

  def history(%Scope{} = scope, %ClassGroup{id: cg_id}, period) do
    key = Organization.period_param(period)

    BulletinPublication
    |> Ash.Query.for_read(:for_class, %{class_group_id: cg_id}, scope: scope)
    |> Ash.Query.filter(period_key == ^key)
    |> Ash.read!()
  end

  @doc "Publishes (freezes) the class's report cards for a trimester or the year."
  def publish(_scope, _cg, {:sequence, _}), do: {:error, :not_publishable}

  def publish(%Scope{} = scope, %ClassGroup{} = cg, {kind, _} = period)
      when kind in [:trimester, :annual] do
    cond do
      current_publication(scope, cg, period) ->
        {:error, :already_published}

      not council_ready?(scope, cg, period) ->
        {:error, :council_not_held}

      needs_annual_council?(scope, cg, period) and not annual_council_held?(scope, cg) ->
        {:error, :annual_council_not_held}

      true ->
        BulletinPublication
        |> Ash.Changeset.for_create(
          :publish,
          %{
            class_group_id: cg.id,
            academic_year_id: cg.academic_year_id,
            term_id: term_id(period),
            period_kind: kind,
            period_key: Organization.period_param(period),
            snapshot: live_view(scope, cg, period)
          },
          scope: scope
        )
        |> Ash.create()
        |> case do
          {:ok, _} = ok ->
            _ = notify_published(scope, cg, period)
            ok

          # A concurrent publish won the race: the partial unique identity refused this one.
          {:error, %Ash.Error.Invalid{}} = error ->
            if current_publication(scope, cg, period),
              do: {:error, :already_published},
              else: error

          other ->
            other
        end
    end
  end

  # The class's form master and teachers hear of the publication; never the publisher.
  # A notification failure must not undo the publication.
  defp notify_published(scope, cg, period) do
    teachers = for tc <- Curriculum.list_assignments_for_class(scope, cg), do: tc.teacher_user_id
    recipients = [cg.form_master_user_id | teachers]
    recipients = Enum.reject(recipients, &(is_nil(&1) or &1 == scope.current_user.id))

    Notifications.deliver(
      scope,
      :bulletins_published,
      recipients,
      %{
        class: cg.label,
        period_kind: elem(period, 0),
        position: period_position(period),
        by: Accounts.User.display_name(scope.current_user)
      },
      "/school/bulletins?class=#{cg.id}&period=#{Organization.period_param(period)}"
    )
  rescue
    error ->
      Logger.warning("bulletins_published notification failed: #{Exception.message(error)}")
      :error
  end

  defp period_position({:trimester, %Term{position: n}}), do: n
  defp period_position(_), do: ""

  @doc "Withdraws a publication; `reason` is required."
  def withdraw(%Scope{} = scope, %BulletinPublication{} = pub, reason) do
    pub
    |> Ash.Changeset.for_update(:withdraw, %{reason: reason}, scope: scope)
    |> Ash.update()
    |> case do
      # Refused because the stored row is no longer published (another page withdrew it).
      {:error, %Ash.Error.Invalid{}} = error ->
        if still_published?(scope, pub), do: error, else: {:error, :not_published}

      other ->
        other
    end
  end

  defp still_published?(scope, %BulletinPublication{id: id}) do
    case Ash.get(BulletinPublication, id, scope: scope) do
      {:ok, %{status: :published}} -> true
      _ -> false
    end
  end

  @doc """
  What the public verification page may say about a student's card in a publication
  (spec I5). The one read outside authentication: it bypasses policies, scoped to the
  workspace the signed token names, and returns no marks.
  """
  def verification(workspace_id, publication_id, student_id) do
    with {:ok, pub} <-
           Ash.get(BulletinPublication, publication_id,
             tenant: workspace_id,
             authorize?: false,
             load: [:workspace, :class_group, :term]
           ),
         %{student: student} <-
           Enum.find(pub.snapshot.roster, &(&1.student.id == student_id)) do
      {pub.status,
       %{
         student_name: student.full_name,
         school_name: pub.workspace.name,
         class_label: pub.class_group.label,
         period_kind: pub.period_kind,
         term_position: pub.term && pub.term.position,
         published_on: published_on(pub),
         withdrawn_on:
           pub.withdrawn_at && pub.withdrawn_at |> DateTime.add(3600) |> DateTime.to_date()
       }}
    else
      _ -> :invalid
    end
  end

  @doc "The school-local (WAT, UTC+1) date of a publication."
  def published_on(%{published_at: at}), do: at |> DateTime.add(3600) |> DateTime.to_date()

  @doc "`:full` (drafts and published), `:published` (published only) or `:none`."
  def access(%Scope{} = scope, %ClassGroup{} = cg) do
    cond do
      Enrollment.class_manager?(scope, cg) -> :full
      teaches_class?(scope, cg) -> :published
      true -> :none
    end
  end

  @doc """
  What `scope` may see of the class's report cards for `period`. Live figures are only
  ever computed for `:full` access.
  """
  def view_for(%Scope{} = scope, %ClassGroup{} = cg, period) do
    case access(scope, cg) do
      :none ->
        :forbidden

      :full ->
        class_view(scope, cg, period)

      :published ->
        case current_publication(scope, cg, period) do
          nil -> :not_published
          pub -> {:published, pub, pub.snapshot}
        end
    end
  end

  @doc "Whether the scope may publish and withdraw (Proviseur, Censeur)."
  def can_publish?(%Scope{current_user: %{} = user, current_workspace: %{id: ws_id}}),
    do: Checks.SchoolRole.holds?(user, ws_id, :admin)

  def can_publish?(_scope), do: false

  @doc "The classes whose report cards the scope may open this year."
  def visible_classes(%Scope{current_user: user} = scope, %AcademicYear{} = year) do
    classes = Enrollment.list_class_groups(scope, year)

    if can_publish?(scope) do
      classes
    else
      taught = taught_class_ids(scope, year)
      Enum.filter(classes, &(&1.form_master_user_id == user.id or MapSet.member?(taught, &1.id)))
    end
  end

  @doc """
  The periods a bulletins page offers: the year's séquences (read-only), then its
  trimesters, then the year. Only trimesters and the year can be published.
  """
  def periods(%Scope{} = scope, %AcademicYear{} = year) do
    terms = Organization.list_terms(scope, year)

    sequences =
      scope
      |> Organization.list_sequences(year)
      |> Enum.sort_by(& &1.number)
      |> Enum.map(fn s ->
        period = {:sequence, s}
        {Organization.period_param(period), gettext("Séquence %{n}", n: s.number), period}
      end)

    trimesters =
      Enum.map(terms, fn t ->
        period = {:trimester, t}
        {Organization.period_param(period), gettext("Trimestre %{n}", n: t.position), period}
      end)

    sequences ++ trimesters ++ [{"annee", gettext("Année"), {:annual, year}}]
  end

  @doc """
  The pre-publish checks for a class and period: marks entered (`rate`, subjects
  without a teacher), conduct marks entered, the class council, and for a class on
  paper the roll calls still to type in (spec 2026-10-28, a warning). Each is
  `%{key, ok?, data}`; the page words them.
  """
  def publish_checklist(%Scope{} = scope, %ClassGroup{} = cg, period, view \\ nil) do
    rate = entry_rate_or_nil(scope, cg, period)
    unassigned = scope |> Curriculum.unassigned_subjects_by_class([cg]) |> Map.get(cg.id, [])
    discipline = Discipline.class_discipline(scope, cg, period)
    entered = Enum.count(discipline, fn {_id, d} -> d.note_de_conduite != nil end)
    council = Councils.council(scope, cg, period)
    stored = if council.id, do: council
    status = Councils.status(stored, false)

    [
      %{
        key: :notes,
        ok?: rate == 100 and unassigned == [],
        data: %{rate: rate, unassigned: length(unassigned)}
      },
      %{
        key: :conduct,
        ok?: entered == map_size(discipline),
        data: %{entered: entered, effectif: map_size(discipline)}
      },
      %{
        key: :council,
        ok?: status == :held,
        data: %{status: status, date: council.held_on, time: council.starts_at}
      }
    ] ++ paper_check(scope, cg, period) ++ v2_checks(scope, cg, period, view)
  end

  # A published bulletin freezes its absences: warn while the period's paper roll
  # calls (up to today) are neither typed in nor marked « non assuré ».
  defp paper_check(_scope, %ClassGroup{paper_roll_call: false}, _period), do: []

  defp paper_check(scope, cg, period) do
    count =
      case Organization.period_date_range(scope, period) do
        {first, last} ->
          last = Enum.min([last, Reference.today()], Date)

          if Date.compare(first, last) == :gt,
            do: 0,
            else:
              scope
              |> Attendance.class_lessons(cg, first, last, Reference.now())
              |> Enum.count(&(&1.status in [:on_paper, :missed]))

        nil ->
          0
      end

    [%{key: :paper_roll_calls, ok?: count == 0, data: %{count: count}}]
  end

  # Spec bulletin v2: the end-of-year council (blocking, enforced by `publish/3`), the
  # APC competences and the one-page fit (both informative).
  # `view`: the live draft when the caller has it, so nothing is computed twice.
  defp v2_checks(_scope, _cg, {:sequence, _}, _view), do: []

  defp v2_checks(scope, cg, period, view) do
    template = (view && Map.get(view, :template)) || template(scope, cg)

    results =
      if view, do: view.results, else: Assessment.class_results_for_period(scope, cg, period)

    Enum.reject(
      [
        annual_council_check(scope, cg, period, template),
        competences_check(scope, cg, period, template),
        page_fit_check(scope, period, template, results)
      ],
      &is_nil/1
    )
  end

  defp annual_council_check(scope, cg, period, template) do
    if needs_annual_council?(scope, cg, period, template) do
      annual = {:annual, Organization.class_year(scope, cg)}
      council = Councils.council(scope, cg, annual)
      status = Councils.status(if(council.id, do: council), false)

      %{
        key: :annual_council,
        ok?: status == :held,
        data: %{status: status, date: council.held_on, time: council.starts_at}
      }
    end
  end

  defp competences_check(scope, cg, {:trimester, _} = period, template) do
    if BulletinTemplate.show?(template, :apc) do
      subjects =
        scope |> Curriculum.list_assignments_for_class(cg) |> Map.new(&{&1.id, &1.subject})

      missing =
        for {ctx_id, lines} <- competences(scope, cg, period),
            Enum.any?(lines, &is_nil(&1.text)),
            do: subjects[ctx_id]

      %{key: :competences, ok?: missing == [], data: %{missing: Enum.sort(missing)}}
    end
  end

  defp competences_check(_scope, _cg, _period, _template), do: nil

  defp page_fit_check(scope, period, template, results) do
    groups =
      (results && results.per_student |> Map.values() |> List.first() |> then(&(&1 && &1.groups))) ||
        []

    lines =
      BulletinLayout.subject_lines(
        template,
        Organization.period_kind(period),
        groups,
        sequences_per_term(period),
        group_subtotals?(scope)
      )

    density = BulletinLayout.density(lines, BulletinLayout.identity_rows(template))
    subjects = groups |> Enum.map(&length(&1.rows)) |> Enum.sum()
    %{key: :page_fit, ok?: density != :overflow, data: %{subjects: subjects}}
  end

  @doc """
  Spec bulletin v2 §5.5: the year's last trimester carrying the annual summary is
  published only once the end-of-year council is held.
  """
  def needs_annual_council?(scope, cg, period, template \\ nil)

  def needs_annual_council?(scope, cg, {:trimester, %Term{} = term}, template) do
    BulletinTemplate.show?(template || template(scope, cg), :annual_summary) and
      last_term?(scope, term)
  end

  def needs_annual_council?(_scope, _cg, _period, _template), do: false

  @doc "Whether the class's end-of-year council is held."
  def annual_council_held?(scope, cg),
    do: Councils.held?(scope, cg, {:annual, Organization.class_year(scope, cg)})

  defp entry_rate_or_nil(_scope, _cg, {:sequence, _}), do: nil
  defp entry_rate_or_nil(scope, cg, period), do: entry_rate(scope, cg, period)

  @doc "The class's mark-entry rate over the period's séquences (rounded down; nil = nothing to measure)."
  def entry_rate(%Scope{} = scope, %ClassGroup{} = cg, {:trimester, %Term{} = term}),
    do: EntryProgress.class_rate(scope, year_of(scope, cg), cg, term.sequences)

  def entry_rate(%Scope{} = scope, %ClassGroup{} = cg, {:annual, %AcademicYear{} = year}),
    do: EntryProgress.class_rate(scope, year, cg, Organization.list_sequences(scope, year))

  defp year_of(%Scope{current_academic_year: %AcademicYear{id: id} = year}, %ClassGroup{
         academic_year_id: id
       }),
       do: year

  defp year_of(_scope, %ClassGroup{academic_year_id: id, workspace_id: ws}),
    do: %AcademicYear{id: id, workspace_id: ws}

  # Spec KLM9: checked against the class's own year, so a teacher keeps access to a past class.
  defp teaches_class?(
         %Scope{current_user: %{}} = scope,
         %ClassGroup{academic_year_id: year_id} = cg
       )
       when is_binary(year_id),
       do: MapSet.member?(taught_class_ids(scope, %AcademicYear{id: year_id}), cg.id)

  defp teaches_class?(_scope, _cg), do: false

  defp taught_class_ids(%Scope{current_user: %{} = user} = scope, year) do
    scope
    |> Curriculum.list_assignments_for_user(year, user)
    |> MapSet.new(& &1.class_group_id)
  end

  defp taught_class_ids(_scope, _year), do: MapSet.new()

  @doc "The council outcome of a student in a view, or nil (no council, version-1 snapshot)."
  def outcome(view, student_id) do
    case Map.get(view, :council) do
      %{outcomes: outcomes} -> Map.get(outcomes, student_id)
      _ -> nil
    end
  end

  @doc "The distinction to show: the council's outcome when there is one, else the computed one."
  def final_distinction(view, student_id, data) do
    case outcome(view, student_id) do
      %{distinction: distinction} -> distinction
      nil -> data && data.distinction
    end
  end

  @doc """
  Élèves redesign: the student's result on the latest published report card of
  the enrollment's class — the year's when published, else the last published
  trimester's — read from the frozen snapshot, never computed. `nil` when none.
  Returns `%{period: :annual | {:trimester, term}, average, rank, effectif}`.
  """
  def latest_published_result(%Scope{} = scope, %{class_group_id: cg_id, student_id: student_id}) do
    BulletinPublication
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(class_group_id == ^cg_id and status == :published)
    |> Ash.Query.load(:term)
    |> Ash.read!()
    |> Enum.max_by(&publication_order/1, fn -> nil end)
    |> published_result(student_id)
  end

  # The year above every trimester, trimesters in their order.
  defp publication_order(%{period_kind: :annual}), do: {1, 0}
  defp publication_order(%{term: %{position: position}}), do: {0, position}

  defp published_result(nil, _student_id), do: nil

  defp published_result(pub, student_id) do
    case pub.snapshot do
      %{results: %{per_student: %{^student_id => data}} = results} ->
        %{
          period: if(pub.period_kind == :annual, do: :annual, else: {:trimester, pub.term}),
          average: data.moyenne_generale,
          rank: data.rank,
          effectif: results.effectif
        }

      _ ->
        nil
    end
  end

  @doc "Classes whose report cards for `period` are published, in one query."
  def published_class_ids(%Scope{} = scope, period) do
    key = Organization.period_param(period)

    BulletinPublication
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(period_key == ^key and status == :published)
    |> Ash.read!()
    |> MapSet.new(& &1.class_group_id)
  end

  # Spec I3/I4: trimester and annual report cards carry their class council; the
  # annual one adds each student's passage decision.
  defp council_entry(scope, cg, {:trimester, %Term{}} = period, results),
    do: council_map(scope, cg, period, results, nil)

  defp council_entry(scope, cg, {:annual, %AcademicYear{}} = period, results) do
    passage = %{
      rules: Assessment.passage_rules(scope),
      students: TeacherAssistant.Councils.passage_inputs(scope, cg, period)
    }

    council_map(scope, cg, period, results, passage)
  end

  defp council_entry(_scope, _cg, _period, _results), do: nil

  defp council_map(scope, cg, period, results, passage) do
    council = TeacherAssistant.Councils.council(scope, cg, period)

    %{
      held?: council.status == :held,
      held_on: council.held_on,
      outcomes: TeacherAssistant.Councils.outcomes(council, results, passage)
    }
  end

  defp council_ready?(scope, cg, period), do: TeacherAssistant.Councils.held?(scope, cg, period)

  defp term_id({:trimester, %Term{id: id}}), do: id
  defp term_id(_), do: nil

  defp plain_entry(%{student: s, enrollment: e}, guardians) do
    %{
      guardians: Map.get(guardians, s.id, []),
      student: %{
        id: s.id,
        full_name: s.full_name,
        matricule: s.matricule,
        national_id: s.national_id,
        sex: s.sex,
        birth_date: s.birth_date,
        birth_place: s.birth_place,
        photo_path: s.photo_path
      },
      enrollment: %{id: e.id, repeater: e.repeater}
    }
  end

  defp plain_discipline(summary) do
    %{
      summary
      | sanctions:
          Enum.map(summary.sanctions, &Map.take(&1, [:id, :type, :date, :reason, :duration_days]))
    }
  end

  defp group_subtotals?(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.bulletin_group_subtotals?
      _ -> false
    end
  end

  # --- Bulletin v2 snapshot pieces --------------------------------------------

  @doc "Whether `term` is the year's last trimester (the end-of-year card)."
  def last_term?(%Scope{} = scope, %Term{} = term) do
    scope
    |> Organization.list_terms(%AcademicYear{id: term.academic_year_id})
    |> Enum.all?(&(&1.position <= term.position))
  end

  # Per teaching context, the period's séquences in order with their competence (or nil).
  defp competences(scope, cg, period) do
    case period_sequences(period) do
      [] ->
        %{}

      seqs ->
        ctx_ids = scope |> Curriculum.list_assignments_for_class(cg) |> Enum.map(& &1.id)
        texts = Assessment.sequence_competences(scope, ctx_ids, Enum.map(seqs, & &1.id))

        Map.new(ctx_ids, fn id ->
          {id,
           Enum.map(
             seqs,
             &%{position: &1.position_in_term, number: &1.number, text: texts[{id, &1.id}]}
           )}
        end)
    end
  end

  defp period_sequences({:trimester, %Term{sequences: seqs}}) when is_list(seqs),
    do: Enum.sort_by(seqs, & &1.position_in_term)

  defp period_sequences({:sequence, %Sequence{} = seq}), do: [seq]
  defp period_sequences(_period), do: []

  defp sequences_per_term({:trimester, %Term{sequences: seqs}}) when is_list(seqs),
    do: length(seqs)

  defp sequences_per_term(_period), do: 1

  # Earlier trimesters' average and rank per student: the published figures when the
  # term is published (what parents saw), else computed now.
  defp prior_terms(scope, cg, {:trimester, %Term{} = term}, template) do
    if BulletinTemplate.show?(template, :previous_terms) do
      scope
      |> Organization.list_terms(%AcademicYear{id: term.academic_year_id})
      |> Enum.filter(&(&1.position < term.position))
      |> Enum.reduce(%{}, fn earlier, acc ->
        scope
        |> term_results(cg, earlier)
        |> Enum.reduce(acc, fn {student_id, d}, acc ->
          line = %{position: earlier.position, average: d.moyenne_generale, rank: d.rank}
          Map.update(acc, student_id, [line], &(&1 ++ [line]))
        end)
      end)
    else
      %{}
    end
  end

  defp prior_terms(_scope, _cg, _period, _template), do: %{}

  defp term_results(scope, cg, term) do
    results =
      case current_publication(scope, cg, {:trimester, term}) do
        nil -> Assessment.class_results_for_period(scope, cg, {:trimester, term})
        pub -> pub.snapshot.results
      end

    (results && results.per_student) || %{}
  end

  # The last trimester's card carries the year (spec bulletin v2 §5.5).
  defp annual_summary(scope, cg, {:trimester, %Term{} = term}, template) do
    if BulletinTemplate.show?(template, :annual_summary) and last_term?(scope, term) do
      year = {:annual, Organization.class_year(scope, cg)}
      results = Assessment.class_results_for_period(scope, cg, year)

      %{
        per_student:
          Map.new((results && results.per_student) || %{}, fn {id, d} ->
            {id, %{average: d.moyenne_generale, rank: d.rank}}
          end),
        council: council_entry(scope, cg, year, results)
      }
    end
  end

  defp annual_summary(_scope, _cg, _period, _template), do: nil
end
