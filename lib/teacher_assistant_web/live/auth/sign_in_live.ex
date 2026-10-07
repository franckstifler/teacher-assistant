defmodule TeacherAssistantWeb.Auth.SignInLive do
  @moduledoc """
  Sign in / register / reset-request pages. Same session contract as
  `AshAuthentication.Phoenix.SignInLive` (it is mounted by `sign_in_route`),
  but renders the library's `Password` component once per strategy instead of
  the all-strategies `SignIn` component, so the phone form gets its own label
  and comes first. Credential handling stays entirely in the library.

  On `/sign-in` a segmented control (« Téléphone | Adresse e-mail ») picks which
  form is visible; both forms stay in the DOM and the switch is client-side
  (`Phoenix.LiveView.JS` sets `data-method` on `#sign-in-methods`, the scoped
  CSS in `layouts/auth.html.heex` hides the other form). Register and reset
  only exist for the email strategy.

  The auth shell has no flash area: a sign-in failure redirected back here by
  `AuthController` (wrong credentials, expired temporary password) is shown as
  the alert block above the forms, and so is a submission the library refuses
  in place (`TeacherAssistantWeb.Auth.SignInForm` reports it) — one generic
  message, never the raw field error.
  """
  use TeacherAssistantWeb, :live_view

  alias AshAuthentication.Info
  alias AshAuthentication.Phoenix.Components
  alias TeacherAssistant.Accounts.User

  @impl true
  def mount(_params, session, socket) do
    overrides = Map.get(session, "overrides", [AshAuthentication.Phoenix.Overrides.Default])

    {:ok,
     socket
     |> assign(:overrides, overrides)
     |> assign(:phone_overrides, [TeacherAssistantWeb.PhoneAuthOverrides | overrides])
     |> assign(:path, session["path"] || "/")
     |> assign(:reset_path, session["reset_path"])
     |> assign(:register_path, session["register_path"])
     |> assign(:current_tenant, session["tenant"])
     |> assign(:context, session["context"] || %{})
     |> assign(:auth_routes_prefix, session["auth_routes_prefix"])
     |> assign(:gettext_fn, session["gettext_fn"])
     |> assign(:phone_strategy, Info.strategy!(User, :phone))
     |> assign(:email_strategy, Info.strategy!(User, :password))
     |> assign(:alert, alert(Phoenix.Flash.get(socket.assigns.flash, :error)))}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # Sent by `TeacherAssistantWeb.Auth.SignInForm` when the library refuses a
  # submission (wrong password, unknown or malformed identifier): one generic
  # message whatever the cause.
  @impl true
  def handle_info({:sign_in_failed, _strategy_name}, socket) do
    {:noreply, assign(socket, :alert, wrong_credentials_alert())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="sign-in-methods"
      class="ta-sign-in-methods w-full"
      data-method={if @live_action == :sign_in, do: "phone", else: "email"}
    >
      <div
        :if={@live_action == :sign_in}
        class="ta-segmented"
        role="group"
        aria-label={gettext("Se connecter avec")}
      >
        <button
          type="button"
          id="sign-in-method-phone"
          class="ta-segmented__option"
          data-option="phone"
          aria-pressed="true"
          phx-click={choose_method("phone")}
        >
          {gettext("Téléphone")}
        </button>
        <button
          type="button"
          id="sign-in-method-email"
          class="ta-segmented__option"
          data-option="email"
          aria-pressed="false"
          phx-click={choose_method("email")}
        >
          {gettext("Adresse e-mail")}
        </button>
      </div>

      <div
        :if={@alert}
        id="sign-in-alert"
        class={["ta-auth-alert", "ta-auth-alert--#{@alert.tone}"]}
        role="alert"
      >
        <.icon
          name={
            if @alert.tone == :warning,
              do: "hero-clock",
              else: "hero-exclamation-circle"
          }
          class="ta-auth-alert__icon size-4"
        />
        <div>
          <p class="ta-auth-alert__title">{@alert.title}</p>
          <p :if={@alert.text} class="ta-auth-alert__text">{@alert.text}</p>
        </div>
      </div>

      <div
        :if={@live_action == :sign_in}
        id="phone-sign-in"
        class="ta-phone-form"
        phx-mounted={phone_keyboard()}
      >
        <.live_component
          module={Components.Password}
          id="phone-strategy"
          strategy={@phone_strategy}
          live_action={:sign_in}
          path={@path}
          auth_routes_prefix={@auth_routes_prefix}
          reset_path={nil}
          register_path={nil}
          overrides={@phone_overrides}
          current_tenant={@current_tenant}
          context={@context}
          gettext_fn={@gettext_fn}
        />

        <div id="phone-forgot-password" class="ta-auth-info">
          <.icon name="hero-information-circle" class="ta-auth-info__icon size-4" />
          <p>
            <strong>{gettext("Mot de passe oublié ?")}</strong>
            {gettext(
              "Demandez-en un nouveau au proviseur ou au censeur : il vous donnera un mot de passe temporaire valable 7 jours."
            )}
          </p>
        </div>
      </div>

      <div id="email-sign-in" class="ta-email-form">
        <.live_component
          module={Components.Password}
          id="email-strategy"
          strategy={@email_strategy}
          live_action={@live_action}
          path={@path}
          auth_routes_prefix={@auth_routes_prefix}
          reset_path={@reset_path}
          register_path={@register_path}
          overrides={@overrides}
          current_tenant={@current_tenant}
          context={@context}
          gettext_fn={@gettext_fn}
        />

        <div :if={@live_action == :reset} id="reset-phone-info" class="ta-auth-info">
          <.icon name="hero-information-circle" class="ta-auth-info__icon size-4" />
          <p>
            {Phoenix.HTML.raw(
              gettext(
                "Vous vous connectez avec un <strong>numéro de téléphone</strong> ? Seul votre établissement peut vous donner un nouveau mot de passe."
              )
            )}
          </p>
        </div>
      </div>

      <p :if={@live_action == :sign_in} id="sign-in-register" class="ta-auth-footnote">
        {gettext("Vous dirigez un établissement ?")}
        <.link navigate={@register_path || ~p"/register"}>
          {gettext("Inscrire mon établissement")}
        </.link>
      </p>
    </div>
    """
  end

  # The library's identity input has no `inputmode` option: ask phones for the
  # numeric keypad once the form is on the page (JS attribute ops survive patches).
  defp phone_keyboard do
    JS.set_attribute({"inputmode", "tel"}, to: "#phone-sign-in input[name$='[phone]']")
    |> JS.set_attribute({"autocomplete", "tel"}, to: "#phone-sign-in input[name$='[phone]']")
  end

  defp choose_method(method) do
    other = if method == "phone", do: "email", else: "phone"

    JS.set_attribute({"data-method", method}, to: "#sign-in-methods")
    |> JS.set_attribute({"aria-pressed", "true"}, to: "#sign-in-method-#{method}")
    |> JS.set_attribute({"aria-pressed", "false"}, to: "#sign-in-method-#{other}")
    |> JS.focus_first(to: "##{method}-sign-in form")
  end

  # The flash comes from `AuthController` (failure / expired temporary password).
  defp alert(nil), do: nil

  defp alert(message) do
    cond do
      message == gettext("Identifiant ou mot de passe incorrect") ->
        wrong_credentials_alert()

      message ==
          gettext("Mot de passe temporaire expiré — demandez-en un nouveau à l'établissement.") ->
        %{
          tone: :warning,
          title: gettext("Mot de passe temporaire expiré"),
          text:
            gettext(
              "Ce mot de passe temporaire avait 7 jours : demandez-en un nouveau à votre établissement."
            )
        }

      true ->
        %{tone: :error, title: message, text: nil}
    end
  end

  defp wrong_credentials_alert do
    %{
      tone: :error,
      title: gettext("Identifiant ou mot de passe incorrect"),
      text: gettext("Vérifiez le numéro (ou l'adresse) et le mot de passe, puis réessayez.")
    }
  end
end
