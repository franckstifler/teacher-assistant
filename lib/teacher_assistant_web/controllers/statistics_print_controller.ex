defmodule TeacherAssistantWeb.StatisticsPrintController do
  @moduledoc """
  « Mes statistiques » on paper (spec audit follow-ups A4): the teacher's table for a
  séquence, a trimester or the year under the school's official header, ready for
  the fiche handed to the Censeur or the conseil d'enseignement. A4 landscape (twelve
  columns). `?period=` as the page (`seq:<id>`, `trim:<id>`, `annee`; the current
  séquence by default); `?teacher=<id>` for the Proviseur and the Censeur.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Assessment, Organization, ReportCards}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.{Reference, TeacherCourses}
  alias TeacherAssistantWeb.Teacher.StatisticsLive

  def show(conn, params) do
    with %{current_academic_year: %{} = year} = scope <- conn.assigns.current_scope,
         {:ok, teacher} <- StatisticsLive.teacher_for(scope, params["teacher"]),
         {_, _} = period <- period(scope, year, params["period"]) do
      rows = Assessment.teacher_statistics(scope, teacher, period)
      template = template(scope, rows)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        rows: rows,
        period: period,
        periods: ReportCards.periods(scope, year),
        chosen: Organization.period_param(period),
        teacher_id: teacher.id != scope.current_user.id && teacher.id,
        teacher_name: User.display_name(teacher),
        year: year.name,
        school: scope.current_workspace.name,
        template: template,
        in_progress?: Organization.period_in_progress?(scope, period),
        printed_on: Reference.today()
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp period(scope, year, param) when is_binary(param) and param != "" do
    Organization.resolve_period(scope, year, param) || period(scope, year, nil)
  end

  defp period(scope, _year, _param) do
    case TeacherCourses.current_sequence(scope) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  # The school's official header, resolved for the first class the teacher teaches.
  defp template(_scope, []), do: nil

  defp template(scope, [%{course: %{classes: [cg | _]}} | _]), do: ReportCards.template(scope, cg)
end
