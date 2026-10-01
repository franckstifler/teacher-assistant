defmodule TeacherAssistant.ReportCards do
  @moduledoc """
  Report-card publication (spec I2). A class's trimester or annual report cards are a
  draft (live figures) until the Proviseur or Censeur publishes them; publishing stores
  `live_view/3` as a snapshot, which every screen then renders instead of live figures.
  Séquence report cards are always live.
  """
  require Ash.Query

  alias TeacherAssistant.{Accounts, Assessment, Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{BulletinPublication, ClassGroup, Term}
  alias TeacherAssistant.Scope

  @doc "What the report card, class results and print render, computed now."
  def live_view(%Scope{} = scope, %ClassGroup{} = cg, period) do
    fm = Enrollment.form_master(scope, cg)

    %{
      results: Assessment.class_results_for_period(scope, cg, period),
      roster: scope |> Enrollment.list_roster(cg) |> Enum.map(&plain_entry/1),
      conduct: Attendance.class_conduct(scope, cg, period),
      discipline:
        scope
        |> Discipline.class_discipline(cg, period)
        |> Map.new(fn {id, summary} -> {id, plain_discipline(summary)} end),
      form_master: fm && %{name: fm.name, email: to_string(fm.email)},
      group_subtotals?: group_subtotals?(scope)
    }
  end

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
    if current_publication(scope, cg, period) do
      {:error, :already_published}
    else
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
        # A concurrent publish won the race: the partial unique identity refused this one.
        {:error, %Ash.Error.Invalid{}} = error ->
          if current_publication(scope, cg, period), do: {:error, :already_published}, else: error

        other ->
          other
      end
    end
  end

  @doc "Withdraws a publication; `reason` is required."
  def withdraw(%Scope{} = scope, %BulletinPublication{} = pub, reason) do
    pub
    |> Ash.Changeset.for_update(:withdraw, %{reason: reason}, scope: scope)
    |> Ash.update()
  end

  @doc "The school-local (WAT, UTC+1) date of a publication."
  def published_on(%{published_at: at}), do: at |> DateTime.add(3600) |> DateTime.to_date()

  defp term_id({:trimester, %Term{id: id}}), do: id
  defp term_id(_), do: nil

  defp plain_entry(%{student: s, enrollment: e}) do
    %{
      student: %{id: s.id, full_name: s.full_name, matricule: s.matricule, sex: s.sex},
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
