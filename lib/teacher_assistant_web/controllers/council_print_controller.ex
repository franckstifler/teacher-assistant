defmodule TeacherAssistantWeb.CouncilPrintController do
  @moduledoc """
  The class council's procès-verbal (spec I3; the annual council's adds the passage
  decisions, spec I4): A4 print of the council header, the class
  statistics, the lists of distinctions and warnings, and one line per student. An open
  council prints "PROJET". Proviseur and Censeur only.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Assessment, Councils, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Academics.{ConductWarning, Distinction, PassageDecision}

  def show(conn, %{"class_id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- ReportCards.can_publish?(scope),
         {:operating, true} <- {:operating, TeacherAssistant.Scope.school_verified?(scope)},
         %{} = year <- scope.current_academic_year,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {_, _} = period <- resolve_period(scope, year, params) do
      council = Councils.council(scope, cg, period)
      {results, outcomes, roster} = figures(scope, cg, period, council)

      rows =
        roster
        |> Enum.map(fn %{student: s} ->
          %{
            student: s,
            data: results && results.per_student[s.id],
            outcome: Map.get(outcomes, s.id)
          }
        end)
        |> Enum.sort_by(
          &{(&1.data && &1.data.rank) || 9_999, String.downcase(&1.student.full_name)}
        )

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        etablissement: scope.current_workspace.name,
        annee: year.name,
        cg: cg,
        period_title: period_title(period),
        annual?: match?({:annual, _}, period),
        council: council,
        results: results,
        rows: rows,
        distinction_groups:
          groups(rows, Distinction.values(), :distinction, &Distinction.label/1),
        warning_groups:
          groups(rows, ConductWarning.values(), :conduct_warning, &ConductWarning.label/1),
        passage_counts: passage_counts(rows),
        draft?: council.status != :held
      )
    else
      {:operating, false} ->
        conn
        |> put_flash(
          :error,
          gettext("École en attente de vérification — impression indisponible.")
        )
        |> redirect(to: ~p"/school")

      _ ->
        redirect(conn, to: ~p"/school")
    end
  end

  defp resolve_period(_scope, year, %{"period" => "annee"}), do: {:annual, year}

  defp resolve_period(scope, year, params) do
    case Enum.find(Organization.list_terms(scope, year), &(&1.id == params["term"])) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  defp period_title({:annual, _}), do: gettext("Conseil de fin d'année")
  defp period_title({:trimester, term}), do: gettext("Trimestre %{n}", n: term.position)

  # A published period prints the figures frozen with its report cards (I2 snapshot);
  # otherwise the live ones (with the passage proposals for the year, spec I4).
  defp figures(scope, cg, period, council) do
    case ReportCards.current_publication(scope, cg, period) do
      %{snapshot: %{council: %{outcomes: outcomes}} = view} ->
        {view.results, outcomes, view.roster}

      _ ->
        results = Assessment.class_results_for_period(scope, cg, period)

        {results, live_outcomes(scope, cg, period, council, results),
         Enrollment.list_roster(scope, cg)}
    end
  end

  defp live_outcomes(scope, cg, {:annual, _} = period, council, results) do
    passage = %{
      rules: Assessment.passage_rules(scope),
      students: Councils.passage_inputs(scope, cg, period)
    }

    Councils.outcomes(council, results, passage)
  end

  defp live_outcomes(_scope, _cg, _period, council, results),
    do: Councils.outcomes(council, results)

  # [{label, count}] for every passage decision, in order.
  defp passage_counts(rows) do
    for value <- PassageDecision.values() do
      {PassageDecision.label(value),
       Enum.count(rows, &match?(%{outcome: %{passage: ^value}}, &1))}
    end
  end

  # [{label, [student names]}] for each value with at least one student.
  defp groups(rows, values, key, label) do
    for value <- values,
        names =
          for(%{outcome: %{^key => ^value}, student: s} <- rows, do: s.full_name),
        names != [],
        do: {label.(value), names}
  end
end
