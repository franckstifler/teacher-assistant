defmodule TeacherAssistantWeb.MarkSheetPrintController do
  @moduledoc """
  « Relevé des notes »: at the end of a séquence the Censeur prints every mark the
  teachers entered so students check theirs before the report cards. One A4
  landscape page per class, a row per student and a column per subject (two, S1 and
  S2, for a trimester), the séquence mark only — no average, no rank. One class, or
  every class with students one after the other.

  `?period=seq:<id>` or `trim:<id>`; without it, the current séquence. Proviseur and
  Censeur only (they see every mark of the school).
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Assessment, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Academics.{Reference, SchoolTemplates}

  def class(conn, %{"id" => id} = params) do
    with %{current_academic_year: %{} = year} = scope <- conn.assigns.current_scope,
         true <- ReportCards.can_publish?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {_, _} = period <- period(scope, year, params["period"]) do
      render_sheets(
        conn,
        scope,
        year,
        [cg],
        period,
        ~p"/school/classes/#{cg.id}/mark-sheet/print"
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def all(conn, params) do
    with %{current_academic_year: %{} = year} = scope <- conn.assigns.current_scope,
         true <- ReportCards.can_publish?(scope),
         {_, _} = period <- period(scope, year, params["period"]) do
      classes =
        scope
        |> Enrollment.list_class_groups(year)
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

      render_sheets(conn, scope, year, classes, period, ~p"/school/mark-sheets/print")
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp render_sheets(conn, scope, year, classes, period, path) do
    seqs = sequences(period)

    sheets =
      for cg <- classes,
          %{students: [_ | _]} = sheet <- [Assessment.mark_sheet(scope, cg, seqs)] do
        Map.merge(sheet, %{class_group: cg, lang: ReportCards.template(scope, cg).language})
      end

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      school: scope.current_workspace.name,
      year: year.name,
      period: period,
      seqs: seqs,
      sheets: sheets,
      choices: choices(scope, year),
      chosen: Organization.period_param(period),
      path: path,
      printed_on: Reference.today()
    )
  end

  # A séquence or a trimester of this year; the current séquence by default.
  defp period(scope, year, param) when is_binary(param) do
    case Organization.resolve_period(scope, year, param) do
      {kind, _} = period when kind in [:sequence, :trimester] -> period
      _ -> period(scope, year, nil)
    end
  end

  defp period(scope, year, _param) do
    case Assessment.default_sequence(Organization.list_sequences(scope, year), Reference.today()) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  defp sequences({:sequence, seq}), do: [seq]
  defp sequences({:trimester, term}), do: Enum.sort_by(term.sequences, & &1.position_in_term)

  # The periods the screen offers: every séquence, then every trimester.
  defp choices(scope, year) do
    Enum.map(Organization.list_sequences(scope, year), &{:sequence, &1}) ++
      Enum.map(Organization.list_terms(scope, year), &{:trimester, &1})
  end
end
