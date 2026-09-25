defmodule TeacherAssistantWeb.TimetablePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts.Permissions

  @days [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]

  def class(conn, %{"id" => id} = _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      timetable = Timetabling.class_timetable(cg)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :class,
        title: cg.label,
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Attendance.list_periods(scope.current_workspace),
        grid: timetable.slots,
        days: @days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def me(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope do
      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :me,
        title: to_string(scope.current_user.email),
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Attendance.list_periods(scope.current_workspace),
        grid: Timetabling.teacher_timetable(scope.current_workspace, scope.current_user),
        days: @days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
