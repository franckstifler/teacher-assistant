defmodule TeacherAssistantWeb.FichePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Workspaces

  def show(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         ws when not is_nil(ws) <- scope.current_workspace,
         {:ok, bundle} <- Academics.fetch_owned_entry_with_context(entry_id, ws) do
      {:ok, lesson_plan} = Academics.ensure_lesson_plan(bundle.entry, bundle.ctx)
      steps = Academics.list_lesson_steps(lesson_plan)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        bundle: bundle,
        lesson_plan: lesson_plan,
        steps: steps,
        enseignant: to_string(user.email)
      )
    else
      _ -> redirect(conn, to: ~p"/teacher")
    end
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
