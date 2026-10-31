defmodule TeacherAssistantWeb.ClassListPrintController do
  @moduledoc """
  Spec 2026-10-31 §1: the class list on paper. The official roster (A) is for the
  people who manage the class — the register tab's rule — in the class's language.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistantWeb.School.ClassShell

  def roster(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :register) do
      template = ReportCards.template(scope, cg)
      year = Organization.class_year(scope, cg)
      form_master = Enrollment.form_master(scope, cg)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:roster,
        cg: cg,
        year: year && year.name,
        form_master: form_master && User.display_name(form_master),
        rows: numbered(Enrollment.list_roster(scope, cg)),
        template: template,
        lang: template.language,
        logo?: template.header.logo?,
        head_name: ReportCards.head_name(scope)
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp numbered(rows), do: Enum.with_index(rows, 1)
end
