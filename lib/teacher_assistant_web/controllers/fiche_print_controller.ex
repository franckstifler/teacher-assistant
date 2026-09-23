defmodule TeacherAssistantWeb.FichePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Curriculum

  def show(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         ws when not is_nil(ws) <- scope.current_workspace,
         {:ok, bundle} <- Curriculum.fetch_owned_entry_with_context(entry_id, ws) do
      {:ok, lesson_plan} = Curriculum.ensure_lesson_plan(bundle.entry, bundle.ctx)
      steps = Curriculum.list_lesson_steps!(lesson_plan.id)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        bundle: bundle,
        lesson_plan: lesson_plan,
        steps: steps,
        enseignant: to_string(user.email),
        etablissement: etablissement(scope)
      )
    else
      _ -> redirect(conn, to: "/teacher")
    end
  end

  defp etablissement(%{current_workspace_type: :school, current_workspace: %{name: name}}),
    do: name

  defp etablissement(_scope), do: nil

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
