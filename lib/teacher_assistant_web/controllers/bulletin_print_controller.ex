defmodule TeacherAssistantWeb.BulletinPrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.ReportCards
  alias TeacherAssistant.Academics.BulletinTemplate
  alias TeacherAssistantWeb.{BulletinPrintHTML, BulletinVerification}

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
          qr_svg: qr_svg(pub, template, student.id)
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
      # A frozen card keeps its logo only while the school still has one (never a broken image).
      logo?: template.header.logo? and logo_present?(scope),
      lang: lang,
      class_average: results && results.class_average
    )
  end

  defp logo_present?(scope) do
    match?({:ok, %{logo_path: path}} when is_binary(path), Accounts.fetch_school_profile(scope))
  end

  # Spec I5: only published cards carry a verification code, and only when chosen.
  defp qr_svg(nil, _template, _student_id), do: nil

  defp qr_svg(pub, template, student_id) do
    if BulletinTemplate.show?(template, :qr_code) do
      token = BulletinVerification.token(pub, student_id)
      BulletinVerification.qr_svg(url(~p"/verify/bulletin/#{token}"))
    end
  end

  defp period_heading({:sequence, seq}), do: "#{gettext("Séquence")} #{seq.number}"
  defp period_heading({:trimester, term}), do: "#{gettext("Trimestre")} #{term.position}"
  defp period_heading({:annual, _}), do: gettext("Année scolaire")
end
