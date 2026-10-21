defmodule TeacherAssistantWeb.FeePaperPrintController do
  @moduledoc """
  Printable return notes and warnings to parents (Fees 2), A5, each with its QR check
  code, in the receipt's style. Fees axis.
  """
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.{FeeControl, Fees}
  alias TeacherAssistantWeb.ReceiptVerification

  def note(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Fees.can_manage_fees?(scope),
         {:ok, paper} <- FeeControl.note(scope, id) do
      render_paper(conn, :note, paper: Map.merge(paper, check(:note, paper.note)))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  def warnings(conn, params) do
    ids = params |> Map.get("ids", "") |> String.split(",", trim: true)

    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Fees.can_manage_fees?(scope),
         {:ok, [_ | _] = papers} <- FeeControl.warnings(scope, Enum.filter(ids, &uuid?/1)) do
      render_paper(conn, :warnings,
        papers: Enum.map(papers, &Map.merge(&1, check(:warning, &1.warning)))
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  @doc "The class's « Contrôle des frais » list, printed (`?date=`, default today)."
  def control(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope

    with %{current_workspace: %{}} <- scope,
         {:ok, cg} <- TeacherAssistant.Enrollment.fetch_owned_class_group(scope, id),
         true <-
           Fees.can_manage_fees?(scope) or TeacherAssistant.Enrollment.class_manager?(scope, cg) do
      date =
        case Date.from_iso8601(params["date"] || "") do
          {:ok, date} -> date
          _ -> TeacherAssistant.Academics.Reference.today()
        end

      render_paper(conn, :control,
        cg: cg,
        date: date,
        school: scope.current_workspace,
        control: FeeControl.class_control(scope, cg, date)
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end

  defp uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  defp check(kind, record) do
    token = ReceiptVerification.token(kind, record)

    check_url =
      case kind do
        :note -> url(~p"/verify/note/#{token}")
        :warning -> url(~p"/verify/warning/#{token}")
      end

    %{
      code: ReceiptVerification.code(token),
      qr: ReceiptVerification.qr_svg(check_url),
      lookup_url: url(~p"/verify/receipt")
    }
  end

  defp render_paper(conn, template, assigns) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(template, assigns)
  end
end
