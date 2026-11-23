defmodule TeacherAssistantWeb.AbsenceTotalsPrintController do
  @moduledoc """
  Spec 2026-11-23: « Bilan des absences » on paper — exactly what the page shows for the
  same `period`, `class` and `seuil` params (`AbsenceTotalsParams`), under the school's
  official header. A4 portrait. Conduct managers only, like the page.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Discipline, ReportCards}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.School.AbsenceTotalsParams

  def show(conn, params) do
    scope = conn.assigns.current_scope

    with true <- Discipline.can_manage_conduct?(scope),
         %{} = year <- scope.current_academic_year,
         {:ok, view} <- AbsenceTotalsParams.resolve(scope, params) do
      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        view: view,
        template: template(scope, view),
        school: scope.current_workspace.name,
        year: year.name,
        printed_on: Reference.today()
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  # The school's official header, resolved for the first class shown (or the school's first).
  defp template(scope, %{groups: [%{class_group: cg} | _]}), do: ReportCards.template(scope, cg)
  defp template(scope, %{class_groups: [cg | _]}), do: ReportCards.template(scope, cg)
  defp template(_scope, _view), do: nil
end
