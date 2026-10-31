defmodule TeacherAssistantWeb.ClassListPrintController do
  @moduledoc """
  Spec 2026-10-31 §1: the class list on paper. The official roster (A) and the
  working list (B) are for the people who manage the class — the register tab's rule;
  a teacher prints only the working list, for a course of their own, pre-filled.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Curriculum, Enrollment, Organization, ReportCards}
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

  def working(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :register) do
      render_working(conn, scope, cg, nil, nil)
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def teacher(conn, %{"id" => ctx_id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, ctx} <- Curriculum.fetch_assigned_teaching_context(scope, ctx_id),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, ctx.class_group_id) do
      render_working(conn, scope, cg, ctx.subject, User.display_name(scope.current_user))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp render_working(conn, scope, cg, subject, teacher) do
    year = Organization.class_year(scope, cg)
    rows = numbered(Enrollment.list_roster(scope, cg))

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:working,
      school: scope.current_workspace.name,
      cg: cg,
      year: year && year.name,
      subject: subject,
      teacher: teacher,
      rows: rows,
      density: density(length(rows))
    )
  end

  # Spec §1 B: one A4 page up to 70 students.
  defp density(count) when count <= 40, do: "normal"
  defp density(count) when count <= 55, do: "compact"
  defp density(_count), do: "dense"

  defp numbered(rows), do: Enum.with_index(rows, 1)
end
