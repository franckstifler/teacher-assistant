defmodule TeacherAssistantWeb.Authz do
  @moduledoc """
  The flashes a LiveView shows when an action is refused by a policy, or fails for
  another reason the user can act on (a closed year, an invalid value).
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def not_allowed_message, do: gettext("Vous n'avez pas l'autorisation d'effectuer cette action.")

  def put_not_allowed(socket),
    do: Phoenix.LiveView.put_flash(socket, :error, not_allowed_message())

  @doc """
  Flashes why `error` (from a failed action) stopped it: the policy refusal, the
  messages of the validations that refused it, or a generic message for anything
  else (framework errors are not shown to the user).
  """
  def put_failure(socket, error),
    do: Phoenix.LiveView.put_flash(socket, :error, failure_message(error))

  def failure_message(%Ash.Error.Forbidden{}), do: not_allowed_message()

  def failure_message(error) when is_exception(error) do
    case Ash.Error.to_error_class(error) do
      %Ash.Error.Forbidden{} ->
        not_allowed_message()

      %Ash.Error.Invalid{errors: errors} ->
        case Enum.flat_map(errors, &validation_message/1) do
          [] -> generic_message()
          messages -> messages |> Enum.uniq() |> Enum.join(" ")
        end

      _ ->
        generic_message()
    end
  end

  def failure_message(_error), do: generic_message()

  defp generic_message, do: gettext("L'action n'a pas abouti. Réessayez.")

  defp validation_message(%{message: message} = error) when is_binary(message) do
    vars = Map.get(error, :vars) || []

    [
      Enum.reduce(vars, message, fn
        {key, value}, acc when is_binary(value) or is_number(value) or is_atom(value) ->
          String.replace(acc, "%{#{key}}", to_string(value))

        _var, acc ->
          acc
      end)
    ]
  end

  defp validation_message(_error), do: []

  @doc "Whether an `AshPhoenix.Form` submit failed because a policy refused it."
  def forbidden_form?(form),
    do: form |> AshPhoenix.Form.raw_errors() |> Enum.any?(&match?(%{class: :forbidden}, &1))
end
