defmodule TeacherAssistantWeb.CardPrintController do
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{Accounts, Enrollment, Organization, ReportCards}
  alias TeacherAssistantWeb.CardVerification

  @doc "Spec 2026-10-12 §9: printable school ID cards, 10 per A4 page."
  def show(conn, %{"id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Enrollment.can_manage_register?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {:ok, rows} <- pick(Enrollment.list_roster(scope, cg), params["student"]) do
      {:ok, profile} = Accounts.fetch_school_profile(scope)
      year = Organization.class_year(scope, cg)
      template = ReportCards.template(scope, cg)
      rows = Enum.sort_by(rows, &String.downcase(&1.student.full_name))
      students = Enum.map(rows, & &1.student)
      contacts = Enrollment.contact_guardians(scope, Enum.map(students, & &1.id))

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        school: scope.current_workspace.name,
        year: year && year.name,
        cg: cg,
        pages:
          rows
          |> Enum.map(fn %{student: student, enrollment: enrollment} ->
            %{student: student, contact: contacts[student.id], qr_svg: qr_svg(enrollment)}
          end)
          |> Enum.chunk_every(10),
        missing: Enum.count(students, &is_nil(&1.photo_path)),
        # Same language rule as the bulletin: the class's sub-system, or bilingual.
        lang: template.language,
        header: template.header,
        logo?: is_binary(profile.logo_path),
        signature?: is_binary(profile.signature_path),
        stamp?: is_binary(profile.stamp_path)
      )
    else
      {:error, :not_in_class} -> redirect(conn, to: ~p"/school/classes/#{id}/photos")
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  # Spec bulletin v2 §7: the card's QR opens the public check of the enrolment.
  defp qr_svg(enrollment) do
    token = CardVerification.token(enrollment.workspace_id, enrollment.id)
    CardVerification.qr_svg(url(~p"/verify/card/#{token}"))
  end

  defp pick(rows, nil), do: {:ok, rows}

  defp pick(rows, student_id) do
    case Enum.filter(rows, &(&1.student.id == student_id)) do
      [] -> {:error, :not_in_class}
      one -> {:ok, one}
    end
  end
end
