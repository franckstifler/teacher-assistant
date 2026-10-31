defmodule TeacherAssistantWeb.TimetablePrintController do
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  def class(conn, %{"id" => id} = _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Enrollment.class_manager?(scope, cg) do
      timetable = Timetabling.class_timetable(scope, cg)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(
        :show,
        frame(scope, :class, cg.label, [%{title: cg.label, grid: timetable.slots}])
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def me(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope do
      title = User.display_name(scope.current_user)
      grid = Timetabling.teacher_timetable(scope, scope.current_user)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show, frame(scope, :teacher, title, [%{title: title, grid: grid}]))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  @doc "Spec 2026-10-31 §2: every teacher's timetable, one page each, for the censeur."
  def teachers(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Timetabling.can_edit_timetable?(scope) do
      sheets =
        scope
        |> Timetabling.all_teacher_timetables()
        |> Enum.map(&%{title: User.display_name(&1.teacher), grid: &1.grid})

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show, frame(scope, :teacher, nil, sheets))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  @doc "Spec 2026-10-31 §3: the « emploi du temps général », one row per class, A3."
  def general(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Timetabling.can_edit_timetable?(scope) do
      calendar = Attendance.school_calendar(scope)
      lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

      classes =
        case scope.current_academic_year do
          nil -> []
          year -> Enrollment.list_class_groups(scope, year)
        end

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:general,
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        classes: classes,
        grid: Timetabling.school_timetable(scope),
        calendar: calendar,
        days: calendar.lesson_days,
        lessons: lessons
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp frame(scope, mode, title, sheets) do
    calendar = Attendance.school_calendar(scope)

    [
      mode: mode,
      title: title,
      sheets: sheets,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      periods: Attendance.list_periods(scope),
      calendar: calendar,
      days: calendar.lesson_days
    ]
  end
end
