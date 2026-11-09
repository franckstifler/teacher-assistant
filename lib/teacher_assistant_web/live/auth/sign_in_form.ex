defmodule TeacherAssistantWeb.Auth.SignInForm do
  @moduledoc """
  The library's `AshAuthentication.Phoenix.Components.Password.SignInForm`,
  unchanged (it still builds the form, checks the credentials and hands the
  sign-in token to `AuthController`), plus one thing: when a submission fails it
  tells the page (`{:sign_in_failed, strategy_name, reason}` to the LiveView
  process, `reason` being `:throttled` or `:wrong_credentials`)
  and hides the field-level errors; and the identity field always shows what
  was typed, not its cast value (a phone typed « 677123456 » would otherwise
  come back as « +237677123456 » next to the +237 chip).

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
  alias TeacherAssistant.Accounts.User.Preparations.ThrottleSignIn

  # « Rester connecté » starts ticked: most sign-ins are on the person's own phone
  # (the box shows only when the strategy offers it). Display only — the action's
  # argument has no default.
  @impl true
  def update(assigns, socket) do
    {:ok, socket} = SignInForm.update(assigns, socket)

    case socket.assigns do
      %{remember_me_field: field, form: %Form{params: params} = form}
      when not is_nil(field) and not is_map_key(params, "remember_me") ->
        {:ok,
         assign(
           socket,
           :form,
           Form.validate(form, Map.put(params, to_string(field), "true"), errors: false)
         )}

      _ ->
        {:ok, socket}
    end
  end

  @impl true
  defdelegate render(assigns), to: SignInForm

  @impl true
  def handle_event("submit", params, socket) do
    {:noreply, socket} = SignInForm.handle_event("submit", params, socket)

    if failed?(socket) do
      reason = if throttled?(socket.assigns.form), do: :throttled, else: :wrong_credentials
      send(self(), {:sign_in_failed, socket.assigns.strategy.name, reason})
      {:noreply, assign(socket, :form, without_errors(socket, params))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("change", params, socket) do
    {:noreply, socket} = SignInForm.handle_event("change", params, socket)
    {:noreply, assign(socket, :form, show_identity_as_typed(socket, params))}
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

    form
    |> Form.validate(kept, errors: false)
    |> show_identity_as_typed(strategy, kept)
  end

  defp show_identity_as_typed(socket, params) do
    %{subject_name: subject_name, strategy: strategy, form: form} = socket.assigns
    show_identity_as_typed(form, strategy, Map.get(params, to_string(subject_name), %{}))
  end

  # The form displays the query's (cast) argument; put the raw text back for
  # display only — every change/submit rebuilds the query from the params.
  defp show_identity_as_typed(
         %Form{source: %Ash.Query{} = query} = form,
         %{identity_field: field},
         params
       ) do
    case Map.get(params, to_string(field)) do
      typed when is_binary(typed) ->
        %{form | source: %{query | arguments: Map.put(query.arguments, field, typed)}}

      _ ->
        form
    end
  end

  defp show_identity_as_typed(form, _strategy, _params), do: form

  defp throttled?(%Form{source: %{errors: errors}}),
    do: Enum.any?(errors, &ThrottleSignIn.throttled?/1)

  defp throttled?(_form), do: false

  # Success either redirects (sign-in token via GET), sets the token params
  # (token via POST) or triggers the form action (no sign-in tokens).
  defp failed?(socket) do
    is_nil(socket.redirected) and !socket.assigns[:trigger_action] and
      is_nil(socket.assigns[:sign_in_token_params])
  end
end
