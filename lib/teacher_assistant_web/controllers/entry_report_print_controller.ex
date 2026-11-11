defmodule TeacherAssistantWeb.EntryReportPrintController do
  @moduledoc """
  The censeur's mark-entry report on paper: for one séquence, every teacher's entry
  rate (the mean of their courses', as on « Suivi de la saisie »), then the teachers
  who have not finished, course by course, under the school's official header.
  A4 portrait. `?seq=<id>` as the page (the default séquence otherwise). Reserved to
  the administration, like the page (`Organization.can_manage_calendar?/1`).
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Assessment, Organization, ReportCards}
  alias TeacherAssistant.Academics.Reference

  def show(conn, params) do
    scope = conn.assigns.current_scope

    with true <- Organization.can_manage_calendar?(scope),
         %{} = year <- scope.current_academic_year,
         [_ | _] = sequences <- Organization.list_sequences(scope, year),
         %{} = seq <- pick(sequences, params["seq"]) do
      grid = Assessment.sequence_entry_grid(scope, year, seq)
      teachers = Assessment.teacher_entry_summary(grid)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        seq: seq,
        sequences: sequences,
        grid: grid,
        teachers: teachers,
        late: Enum.filter(teachers, &(&1.late != [])),
        template: template(scope, grid),
        school: scope.current_workspace.name,
        year: year.name,
        printed_on: Reference.today()
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  # An id that is not one of this year's séquences falls back to the default one.
  defp pick(sequences, id) when is_binary(id),
    do: Enum.find(sequences, &(&1.id == id)) || pick(sequences, nil)

  defp pick(sequences, _id), do: Assessment.default_sequence(sequences, Reference.today())

  # The school's official header, resolved for its first class.
  defp template(scope, %{rows: [%{class_group: cg} | _]}), do: ReportCards.template(scope, cg)
  defp template(_scope, _grid), do: nil
end
