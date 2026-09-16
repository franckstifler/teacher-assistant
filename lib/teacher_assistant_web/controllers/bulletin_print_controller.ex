defmodule TeacherAssistantWeb.BulletinPrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Accounts.{Permissions, Workspaces}

  def show(conn, %{"id" => id, "enrollment_id" => eid} = params) do
    with_class(conn, id, params, fn scope, cg, period, results ->
      roster = Academics.list_roster(cg)

      case Enum.find(roster, &(&1.enrollment.id == eid)) do
        %{} = entry -> render_bulletins(conn, scope, cg, period, results, [entry])
        nil -> redirect(conn, to: ~p"/school/classes/#{id}/results")
      end
    end)
  end

  def class(conn, %{"id" => id} = params) do
    with_class(conn, id, params, fn scope, cg, period, results ->
      entries =
        cg
        |> Academics.list_roster()
        |> Enum.sort_by(&String.downcase(&1.student.full_name))

      render_bulletins(conn, scope, cg, period, results, entries)
    end)
  end

  # Resolves scope + admin + class + period, then hands off to `fun`.
  defp with_class(conn, id, params, fun) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         year when not is_nil(year) <- scope.current_academic_year,
         period when not is_nil(period) <- Academics.resolve_period(year, params["period"]) do
      fun.(scope, cg, period, Academics.class_results_for_period(cg, period))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp render_bulletins(conn, scope, cg, period, results, entries) do
    conduct_by_enrollment = Attendance.class_conduct(cg, period)
    discipline_by_enrollment = Discipline.class_discipline(cg, period)

    bundles =
      Enum.map(entries, fn %{student: student, enrollment: enrollment} ->
        %{
          student: student,
          enrollment: enrollment,
          data: results && results.per_student[student.id],
          conduct: conduct_by_enrollment[enrollment.id],
          discipline: discipline_by_enrollment[enrollment.id]
        }
      end)

    fm = Academics.form_master(cg)

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      professeur_principal: fm && fm.email,
      cg: cg,
      period_kind: Academics.period_kind(period),
      period_heading: period_heading(period),
      effectif: (results && results.effectif) || 0,
      bundles: bundles
    )
  end

  defp period_heading({:sequence, seq}), do: "#{gettext("Séquence")} #{seq.number}"
  defp period_heading({:trimester, term}), do: "#{gettext("Trimestre")} #{term.position}"
  defp period_heading({:annual, _}), do: gettext("Année scolaire")

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
