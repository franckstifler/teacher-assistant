defmodule TeacherAssistantWeb.TimetablePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.{Permissions, Workspaces}

  @days [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]

  def class(conn, %{"id" => id} = _params) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      timetable = Timetables.class_timetable(cg)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :class,
        title: cg.label,
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Timetables.list_periods(scope.current_workspace),
        grid: timetable.slots,
        days: @days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def me(conn, _params) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         :school <- scope.current_workspace_type do
      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        mode: :me,
        title: to_string(user.email),
        etablissement: scope.current_workspace.name,
        annee: scope.current_academic_year && scope.current_academic_year.name,
        periods: Timetables.list_periods(scope.current_workspace),
        grid: Timetables.teacher_timetable(scope.current_workspace, user),
        days: @days
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
