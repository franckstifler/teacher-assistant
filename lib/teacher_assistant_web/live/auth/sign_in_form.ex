defmodule TeacherAssistantWeb.Auth.SignInForm do
  @moduledoc """
  The library's `AshAuthentication.Phoenix.Components.Password.SignInForm`,
  unchanged (it still builds the form, checks the credentials and hands the
  sign-in token to `AuthController`), plus one thing: when a submission fails it
  tells the page (`{:sign_in_failed, strategy_name}` to the LiveView process)
  and hides the field-level errors.

  Why: a wrong password ("Phone or password was incorrect") and a malformed
  number (the `Phone` cast error) would otherwise surface as raw, English,
  field-level messages — and a cast error even tells an attacker which half was
  wrong. `TeacherAssistantWeb.Auth.SignInLive` shows one generic
  « Identifiant ou mot de passe incorrect » alert instead.

  Wired through the `sign_in_form_module` key of `Components.Password` in
  `TeacherAssistantWeb.AuthOverrides`.
  """
  use Phoenix.LiveComponent

  alias AshAuthentication.Phoenix.Components.Password.SignInForm
  alias AshPhoenix.Form

  @impl true
  defdelegate update(assigns, socket), to: SignInForm

  @impl true
  defdelegate render(assigns), to: SignInForm

  @impl true
  def handle_event("submit", params, socket) do
    {:noreply, socket} = SignInForm.handle_event("submit", params, socket)

    if failed?(socket) do
      send(self(), {:sign_in_failed, socket.assigns.strategy.name})
      {:noreply, assign(socket, :form, without_errors(socket, params))}
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, params, socket), do: SignInForm.handle_event(event, params, socket)

  # Keeps what was typed in the identity field, empties the password, shows no
  # field errors (the page-level alert says what happened).
  defp without_errors(socket, params) do
    %{subject_name: subject_name, strategy: strategy, form: form} = socket.assigns

    kept =
      params
      |> Map.get(to_string(subject_name), %{})
      |> Map.delete(to_string(strategy.password_field))

    Form.validate(form, kept, errors: false)
  end

  # Success either redirects (sign-in token via GET), sets the token params
  # (token via POST) or triggers the form action (no sign-in tokens).
  defp failed?(socket) do
    is_nil(socket.redirected) and !socket.assigns[:trigger_action] and
      is_nil(socket.assigns[:sign_in_token_params])
  end
end
