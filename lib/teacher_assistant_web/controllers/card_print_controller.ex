defmodule TeacherAssistantWeb.CardPrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Accounts, Enrollment, Organization, ReportCards}

  @doc "Spec 2026-10-12 §9: printable school ID cards, 10 per A4 page."
  def show(conn, %{"id" => id} = params) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Enrollment.can_manage_register?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         {:ok, rows} <- pick(Enrollment.list_roster(scope, cg), params["student"]) do
      {:ok, profile} = Accounts.fetch_school_profile(scope)
      year = Organization.class_year(scope, cg)
      students = rows |> Enum.map(& &1.student) |> Enum.sort_by(&String.downcase(&1.full_name))

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        school: scope.current_workspace.name,
        year: year && year.name,
        cg: cg,
        pages:
          students
          |> Enum.map(&%{student: &1, contact: contact(scope, &1)})
          |> Enum.chunk_every(10),
        missing: Enum.count(students, &is_nil(&1.photo_path)),
        # Same language rule as the bulletin: the class's sub-system, or bilingual.
        lang: ReportCards.template(scope, cg).language,
        logo?: is_binary(profile.logo_path),
        signature?: is_binary(profile.signature_path),
        stamp?: is_binary(profile.stamp_path)
      )
    else
      {:error, :not_in_class} -> redirect(conn, to: ~p"/school/classes/#{id}/photos")
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp pick(rows, nil), do: {:ok, rows}

  defp pick(rows, student_id) do
    case Enum.filter(rows, &(&1.student.id == student_id)) do
      [] -> {:error, :not_in_class}
      one -> {:ok, one}
    end
  end

  # Main contact first (list_guardian_links orders it so), else the first linked guardian.
  defp contact(scope, student) do
    case Enrollment.list_guardian_links(scope, student) do
      [%{guardian: g} | _] -> g
      _ -> nil
    end
  end
end
