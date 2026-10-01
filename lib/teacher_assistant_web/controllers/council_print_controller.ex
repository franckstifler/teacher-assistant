defmodule TeacherAssistantWeb.CouncilPrintController do
  @moduledoc """
  The class council's procès-verbal (spec I3): A4 print of the council header, the class
  statistics, the lists of distinctions and warnings, and one line per student. An open
  council prints "PROJET". Proviseur and Censeur only.
  """
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Assessment, Councils, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Academics.{ConductWarning, Distinction}

  def show(conn, %{"class_id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- ReportCards.can_publish?(scope),
         {:operating, true} <- {:operating, TeacherAssistant.Scope.school_verified?(scope)},
         %{} = year <- scope.current_academic_year,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         %{} = term <-
           Enum.find(Organization.list_terms(scope, year), &(&1.id == params["term"])) do
      council = Councils.council(scope, cg, term)
      results = Assessment.class_results_for_period(scope, cg, {:trimester, term})
      outcomes = Councils.outcomes(council, results)

      rows =
        scope
        |> Enrollment.list_roster(cg)
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
        term: term,
        council: council,
        results: results,
        rows: rows,
        distinction_groups:
          groups(rows, Distinction.values(), :distinction, &Distinction.label/1),
        warning_groups:
          groups(rows, ConductWarning.values(), :conduct_warning, &ConductWarning.label/1),
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

  # [{label, [student names]}] for each value with at least one student.
  defp groups(rows, values, key, label) do
    for value <- values,
        names =
          for(%{outcome: %{^key => ^value}, student: s} <- rows, do: s.full_name),
        names != [],
        do: {label.(value), names}
  end
end
