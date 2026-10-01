defmodule TeacherAssistantWeb.TimetablePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  def class(conn, %{"id" => id} = _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Enrollment.class_manager?(scope, cg) do
      timetable = Timetabling.class_timetable(scope, cg)
      calendar = Attendance.school_calendar(scope)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :class,
        title: cg.label,
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Attendance.list_periods(scope),
        grid: timetable.slots,
        calendar: calendar,
        days: calendar.lesson_days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def me(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope do
      calendar = Attendance.school_calendar(scope)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :me,
        title: to_string(scope.current_user.email),
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Attendance.list_periods(scope),
        grid: Timetabling.teacher_timetable(scope, scope.current_user),
        calendar: calendar,
        days: calendar.lesson_days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
