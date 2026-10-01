defmodule TeacherAssistantWeb.BulletinPrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.ReportCards
  alias TeacherAssistantWeb.BulletinPrintHTML

  def show(conn, %{"id" => id, "enrollment_id" => eid} = params) do
    with_view(conn, id, params, fn scope, cg, period, status, pub, view ->
      case Enum.find(view.roster, &(&1.enrollment.id == eid)) do
        %{} = entry -> render_bulletins(conn, scope, cg, period, status, pub, view, [entry])
        nil -> redirect(conn, to: ~p"/school/classes/#{id}/results")
      end
    end)
  end

  def class(conn, %{"id" => id} = params) do
    with_view(conn, id, params, fn scope, cg, period, status, pub, view ->
      entries = Enum.sort_by(view.roster, &String.downcase(&1.student.full_name))
      render_bulletins(conn, scope, cg, period, status, pub, view, entries)
    end)
  end

  # Resolves scope + class + period, then what the user may see (spec I2): a
  # published snapshot, a live draft (class managers), or nothing yet.
  defp with_view(conn, id, params, fun) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {:operating, true} <- {:operating, TeacherAssistant.Scope.school_verified?(scope)},
         year when not is_nil(year) <- scope.current_academic_year,
         period when not is_nil(period) <-
           Organization.resolve_period(scope, year, params["period"]) do
      case ReportCards.view_for(scope, cg, period) do
        {:published, pub, view} ->
          fun.(scope, cg, period, :published, pub, view)

        {:draft, view} ->
          fun.(scope, cg, period, :draft, nil, view)

        :not_published ->
          conn
          |> put_flash(:error, gettext("Pas encore publiés"))
          |> redirect(to: ~p"/school/classes/#{cg.id}/results?period=#{params["period"]}")

        :forbidden ->
          redirect(conn, to: ~p"/school")
      end
    else
      {:operating, false} ->
        conn
        |> put_flash(
          :error,
          gettext("École en attente de vérification — impression indisponible.")
        )
        |> redirect(to: ~p"/school")

      _ ->
        redirect(conn, to: ~p"/school")
    end
  end

  defp render_bulletins(conn, scope, cg, period, status, pub, view, entries) do
    results = view.results
    template = ReportCards.template_of(scope, cg, view)
    lang = template.language

    bundles =
      Enum.map(entries, fn %{student: student, enrollment: enrollment} ->
        %{
          student: student,
          enrollment: enrollment,
          data: results && results.per_student[student.id],
          outcome: ReportCards.outcome(view, student.id),
          distinction:
            ReportCards.final_distinction(
              view,
              student.id,
              results && results.per_student[student.id]
            ),
          conduct: view.conduct[enrollment.id],
          discipline: view.discipline[enrollment.id],
          qr_svg: nil
        }
      end)

    kind = Organization.period_kind(period)

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      professeur_principal: view.form_master && view.form_master.email,
      cg: cg,
      period_kind: kind,
      period_heading: BulletinPrintHTML.tr(lang, fn -> period_heading(period) end),
      effectif: (results && results.effectif) || 0,
      bundles: bundles,
      group_subtotals?: view.group_subtotals?,
      draft?: status == :draft and kind in [:trimester, :annual],
      published_on: pub && Calendar.strftime(ReportCards.published_on(pub), "%d/%m/%Y"),
      template: template,
      lang: lang,
      class_average: results && results.class_average
    )
  end

  defp period_heading({:sequence, seq}), do: "#{gettext("Séquence")} #{seq.number}"
  defp period_heading({:trimester, term}), do: "#{gettext("Trimestre")} #{term.position}"
  defp period_heading({:annual, _}), do: gettext("Année scolaire")
end
