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
  alias TeacherAssistant.Academics.SchoolTemplates
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
      render_working(conn, scope, [sheet(scope, cg, nil)], list_title(cg))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def teacher(conn, %{"id" => ctx_id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, ctx} <- Curriculum.fetch_assigned_teaching_context(scope, ctx_id),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, ctx.class_group_id) do
      render_working(conn, scope, [sheet(scope, cg, ctx.subject)], list_title(cg))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  @doc """
  Every working list of the signed-in teacher's courses this year, one A4 page per
  course (a combined course gives one page per class), in class order — for their
  mark sheets.
  """
  def teacher_all(conn, _params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         [_ | _] = contexts <- my_contexts(scope) do
      sheets = Enum.map(contexts, &sheet(scope, &1.class_group, &1.subject))
      render_working(conn, scope, sheets, gettext("Mes listes de classe"))
    else
      [] ->
        conn
        |> put_flash(:info, gettext("Aucun cours attribué : pas de liste à imprimer."))
        |> redirect(to: ~p"/school/courses")

      _ ->
        redirect(conn, to: ~p"/school")
    end
  end

  defp my_contexts(scope) do
    scope
    |> Curriculum.list_units_for_scope()
    |> Enum.flat_map(fn
      {:solo, tc} -> [tc]
      {:course, course} -> Curriculum.contexts_of_course!(course.id, scope: scope)
    end)
    # `:class_group` is multitenant: the load needs the scope.
    |> Ash.load!(:class_group, scope: scope)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.sort_by(&{SchoolTemplates.class_sort_key(&1.class_group), &1.subject})
  end

  defp sheet(scope, cg, subject) do
    year = Organization.class_year(scope, cg)
    rows = numbered(Enrollment.list_roster(scope, cg))

    %{
      cg: cg,
      year: year && year.name,
      subject: subject,
      teacher: subject && User.display_name(scope.current_user),
      rows: rows,
      density: density(length(rows))
    }
  end

  defp list_title(cg), do: gettext("Liste de classe") <> " — " <> cg.label

  defp render_working(conn, scope, sheets, title) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:working, school: scope.current_workspace.name, sheets: sheets, title: title)
  end

  # Spec §1 B: one A4 page up to 70 students.
  defp density(count) when count <= 40, do: "normal"
  defp density(count) when count <= 55, do: "compact"
  defp density(_count), do: "dense"

  defp numbered(rows), do: Enum.with_index(rows, 1)
end
