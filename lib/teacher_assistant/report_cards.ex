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

  alias TeacherAssistant.Accounts.Checks

  alias TeacherAssistant.Academics.{
    AcademicYear,
    BulletinPublication,
    BulletinTemplate,
    ClassGroup,
    EntryProgress,
    Term
  }

  alias TeacherAssistant.Scope

  @doc "What the report card, class results and print render, computed now."
  def live_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    fm = Enrollment.form_master(scope, cg)
    results = Assessment.class_results_for_period(scope, cg, period)

    %{
      results: results,
      council: council_entry(scope, cg, period, results),
      roster: scope |> Enrollment.list_roster(cg) |> Enum.map(&plain_entry/1),
      conduct: Attendance.class_conduct(scope, cg, period),
      discipline:
        scope
        |> Discipline.class_discipline(cg, period)
        |> Map.new(fn {id, summary} -> {id, plain_discipline(summary)} end),
      form_master:
        fm && %{name: fm.name, email: fm.email && to_string(fm.email), phone: fm.phone},
      group_subtotals?: group_subtotals?(scope),
      template: template(scope, cg)
    }
  end

  @doc "The class's printed-card template under the school's current settings (spec I5)."
  def template(%Scope{} = scope, %ClassGroup{} = cg) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    BulletinTemplate.resolve(profile, scope.current_workspace.name, cg)
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

  @doc "The publishable periods of the year: its trimesters, then the year."
  def periods(%Scope{} = scope, %AcademicYear{} = year) do
    terms =
      scope
      |> Organization.list_terms(year)
      |> Enum.map(fn t ->
        period = {:trimester, t}
        {Organization.period_param(period), gettext("Trimestre %{n}", n: t.position), period}
      end)

    terms ++ [{"annee", gettext("Année"), {:annual, year}}]
  end

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

  defp plain_entry(%{student: s, enrollment: e}) do
    %{
      student: %{
        id: s.id,
        full_name: s.full_name,
        matricule: s.matricule,
        sex: s.sex,
        birth_date: s.birth_date,
        birth_place: s.birth_place
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
end
