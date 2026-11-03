defmodule TeacherAssistant.Pilotage do
  @moduledoc """
  The Proviseur dashboard's « À traiter » facts (spec 2026-10-09 §1.4, §2.1): reads
  only, no new data. Each fact backs one to-do row, shown only when it holds.
  """

  alias TeacherAssistant.{
    Accounts,
    Assessment,
    Councils,
    Curriculum,
    Enrollment,
    Organization,
    ReportCards,
    Scope
  }

  alias TeacherAssistant.Academics.{Reference, SchoolTemplates}

  @doc """
  The to-do facts of the scope's current year:

    * `classes_without_pp` — classes without a form master (`:enrollment_count` loaded),
      in class order; `class_count` — how many classes the year has;
    * `unassigned` — `%{class: label, subject: name}` for every subject the coefficient
      grid expects in a class that has no teacher yet;
    * `pending_accounts` — `%{count, expired, total}`: members who have not yet signed in
      with their temporary password, how many of those passwords have expired, and how
      many members the school has;
    * `councils_to_plan` — classes whose council of the current term (`councils_term`,
      nil without terms) is still to plan;
    * `pending_corrections` / `oldest_correction` — mark corrections awaiting a decision
      and the date of the oldest one (nil when none).
  """
  def todo(%Scope{} = scope) do
    classes = classes(scope)
    corrections = Assessment.list_corrections(scope, :pending)
    term = current_term(scope)

    %{
      classes_without_pp: Enum.filter(classes, &is_nil(&1.form_master_user_id)),
      class_count: length(classes),
      unassigned: unassigned(scope, classes),
      pending_accounts: pending_accounts(scope),
      councils_to_plan: councils_to_plan(scope, term, classes),
      councils_term: term,
      pending_corrections: length(corrections),
      oldest_correction:
        case corrections do
          [] -> nil
          [oldest | _] -> DateTime.to_date(oldest.inserted_at)
        end
    }
  end

  defp classes(%Scope{current_academic_year: nil}), do: []

  defp classes(%Scope{current_academic_year: year} = scope) do
    scope
    |> Enrollment.list_class_groups(year, load: [:enrollment_count])
    |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)
  end

  # The same cells as the assignments overview's `:to_assign` ones, from three reads.
  defp unassigned(_scope, []), do: []

  defp unassigned(scope, classes) do
    by_class = Curriculum.unassigned_subjects_by_class(scope, classes)

    for cg <- classes,
        subject <- Map.get(by_class, cg.id, []),
        do: %{class: cg.label, subject: subject.name}
  end

  defp pending_accounts(scope) do
    members = Accounts.list_members(scope)

    waiting =
      members
      |> Enum.map(& &1.user)
      |> Enum.filter(&match?(%{must_change_password: true}, &1))

    %{
      count: length(waiting),
      expired: Enum.count(waiting, &Accounts.temporary_password_expired?/1),
      total: length(members)
    }
  end

  defp current_term(%Scope{current_academic_year: nil}), do: nil

  defp current_term(%Scope{current_academic_year: year} = scope),
    do: Councils.default_term(Organization.list_terms(scope, year), Reference.today())

  defp councils_to_plan(_scope, nil, _classes), do: 0
  defp councils_to_plan(_scope, _term, []), do: 0

  defp councils_to_plan(scope, term, classes) do
    period = {:trimester, term}
    councils = Councils.for_period(scope, period)
    published = ReportCards.published_class_ids(scope, period)

    Enum.count(classes, fn cg ->
      Councils.status(Map.get(councils, cg.id), MapSet.member?(published, cg.id)) == :to_plan
    end)
  end

  @doc """
  Each course's APC competence for `seq` (`Assessment.competences_due/3` over the
  courses of a `Assessment.sequence_entry_grid/3`): `%{context_id => text | nil}`, or
  nil when none is due (not an APC school, or `seq` not started).
  """
  def competences(%Scope{} = scope, seq, %{rows: rows}) do
    ids = for row <- rows, %{teaching_context: tc} <- Map.values(row.cells), do: tc.id
    Assessment.competences_due(scope, seq, ids)
  end

  @doc """
  How many courses with students still lack their competence (« N cours sans
  compétence »); 0 when none is due (`competences` nil).
  """
  def competence_gaps(_grid, nil), do: 0

  def competence_gaps(%{rows: rows}, competences) do
    Enum.count(
      for(row <- rows, cell <- Map.values(row.cells), do: cell),
      &competence_missing?(competences, &1)
    )
  end

  @doc "Whether a grid cell (a course with students) still lacks its due competence."
  def competence_missing?(nil, _cell), do: false
  def competence_missing?(_competences, nil), do: false
  def competence_missing?(_competences, %{pct: nil}), do: false

  def competence_missing?(competences, cell),
    do: is_nil(competences[cell.teaching_context.id])
end
