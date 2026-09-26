defmodule TeacherAssistantWeb.Authz do
  @moduledoc "The one flash a LiveView shows when a policy refuses an action."
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def not_allowed_message, do: gettext("Vous n'avez pas l'autorisation d'effectuer cette action.")

  def put_not_allowed(socket),
    do: Phoenix.LiveView.put_flash(socket, :error, not_allowed_message())

  @doc "Whether an `AshPhoenix.Form` submit failed because a policy refused it."
  def forbidden_form?(form),
    do: form |> AshPhoenix.Form.raw_errors() |> Enum.any?(&match?(%{class: :forbidden}, &1))
end
