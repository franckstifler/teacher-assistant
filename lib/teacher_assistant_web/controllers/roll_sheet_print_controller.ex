defmodule TeacherAssistantWeb.RollSheetPrintController do
  @moduledoc """
  Paper roll call (spec 2026-10-28 §2): the weekly roll-call sheet, one A4 landscape
  page per class — one class, or every class on paper. `?week=` is any date of the
  week; without it, the week `PaperRollCall.default_week/1` picks.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Attendance, Discipline, Enrollment}
  alias TeacherAssistant.Academics.{PaperRollCall, Reference}

  def class(conn, %{"id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Discipline.can_manage_conduct?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id) do
      render_sheets(conn, scope, [cg], week(params))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def all(conn, params) do
    with %{current_workspace: %{}, current_academic_year: %{} = year} = scope <-
           conn.assigns.current_scope,
         true <- Discipline.can_manage_conduct?(scope) do
      classes = scope |> Enrollment.list_class_groups(year) |> Enum.filter(& &1.paper_roll_call)
      render_sheets(conn, scope, classes, week(params))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp render_sheets(conn, scope, classes, monday) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      sheets:
        Enum.map(classes, &%{class_group: &1, week: Attendance.paper_week(scope, &1, monday)})
    )
  end

  defp week(%{"week" => week}) when is_binary(week) do
    case Date.from_iso8601(week) do
      {:ok, date} -> Date.beginning_of_week(date)
      _ -> PaperRollCall.default_week(Reference.today())
    end
  end

  defp week(_params), do: PaperRollCall.default_week(Reference.today())
end
