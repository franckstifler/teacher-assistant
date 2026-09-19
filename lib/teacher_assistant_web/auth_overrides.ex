defmodule TeacherAssistantWeb.AuthOverrides do
  @moduledoc """
  Branding + layout overrides for the AshAuthentication.Phoenix pages
  (sign in, register, reset, magic link, confirm, sign out).

  These compose on top of `AshAuthentication.Phoenix.Overrides.DaisyUI`
  (declared after it in the router), so we only set the keys we want to
  change.

  Sign in / register / reset / magic-link render inside the split-screen
  `Layouts.auth` layout (wired in the router), which now carries the
  "paper" identity (public, pre-login world — the same look as the landing
  page) rather than the Tableau chalkboard: a dark brand panel beside a
  white form column with boxed inputs (`.ta-auth-paper` in
  `layouts/auth.html.heex` supplies the palette; every class we set below
  is either a plain Tailwind layout utility or a small marker class that
  CSS block styles). Confirm and sign-out are NOT wrapped by that layout
  (they render on their own full-screen backdrop), so they keep the
  original Tableau board card.

  Magic-link sign-in is de-emphasized per the current design: the
  "request a magic link" form is still fully configured and its routes
  still work (nothing is removed from the router or the resource), it's
  just visually hidden (`hidden`) on the sign-in/register pages, along
  with the divider that used to separate it from the password form.

  Password strategy notes:

    * "Rester connecté" is a best-effort, presentational-only checkbox —
      the `password` strategy has no `remember_me` add-on configured on
      `TeacherAssistant.Accounts.User`, so there's nothing to wire it to.
      It's rendered via `sign_in_extra_component` and isn't part of the
      submitted form (no `name`), so it can't corrupt sign-in params.
    * "Mot de passe oublié ?" is real: the password strategy now has a
      `resettable` block (see `TeacherAssistant.Accounts.User`), so the
      request-reset step and the `/password-reset/:token` step both work.
  """
  use AshAuthentication.Phoenix.Overrides
  use Phoenix.Component

  alias AshAuthentication.Phoenix.{
    Components,
    ConfirmLive,
    MagicSignInLive,
    ResetLive,
    SignInLive,
    SignOutLive
  }

  # forms wrapped by Layouts.auth render flat inside its form column
  @page_wrapped "w-full"
  # confirm / sign-out stand on their own full-screen backdrop
  @page_standalone "ta-auth-bg min-h-screen grid place-items-center p-4"
  @card_standalone "ta-board w-full max-w-md mx-auto px-6 py-8 sm:px-8"

  @heading "ta-display mb-6 text-2xl font-semibold text-base-content"

  # --- page roots -----------------------------------------------------------

  override SignInLive do
    set :root_class, @page_wrapped
  end

  override MagicSignInLive do
    set :root_class, @page_wrapped
  end

  override ResetLive do
    set :root_class, @page_wrapped
  end

  override ConfirmLive do
    set :root_class, @page_standalone
  end

  override SignOutLive do
    set :root_class, @page_standalone
  end

  # --- the form containers --------------------------------------------------

  override Components.SignIn do
    set :root_class, "w-full"
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "ta-auth-error"
    set :authentication_error_text_class, ""
    set :strategy_display_order, :forms_first
    set :show_banner, false
  end

  override Components.Reset do
    set :root_class, "w-full"
    set :strategy_class, "w-full"
    set :show_banner, false
  end

  override Components.Confirm do
    set :root_class, @card_standalone
    set :strategy_class, "w-full"
  end

  override Components.SignOut do
    set :root_class, @card_standalone
    set :h2_class, "#{@heading} text-center"
    set :h2_text, "À bientôt"
    set :info_text, "Voulez-vous vraiment vous déconnecter ?"
    set :info_text_class, "text-sm text-base-content/65 mb-4 text-center"
    set :button_text, "Se déconnecter"
    set :button_class, "btn btn-primary btn-block"
  end

  # --- wordmark banner — hidden; the paper layout's brand panel carries the
  # wordmark on every viewport (it stacks on top on phones, so there's no
  # separate mobile-only banner needed the way the Tableau layout had one) --

  override Components.Banner do
    set :root_class, "hidden"
  end

  # --- magic link: keep the strategy/route working, hide the UI -------------

  override Components.MagicLink do
    set :root_class, "hidden"
  end

  override Components.HorizontalRule do
    set :root_class, "hidden"
  end

  # --- password: French copy, boxed fields, remember-me + forgot-password ---

  override Components.Password do
    set :root_class, "w-full"
    set :interstitial_class, "ta-toggler-row"
    set :toggler_class, nil
    set :sign_in_toggle_text, "Se connecter"
    set :register_toggle_text, "Créer un compte"
    set :reset_toggle_text, "Mot de passe oublié ?"
    set :show_first, :sign_in
    set :hide_class, "hidden"
    set :sign_in_extra_component, &__MODULE__.remember_me_extra/1
    set :register_extra_component, &__MODULE__.name_extra/1
  end

  override Components.Password.SignInForm do
    set :form_class, "flex flex-col"
    set :slot_class, nil
    set :button_text, "Se connecter"
    set :disable_button_text, "Connexion…"
  end

  override Components.Password.RegisterForm do
    set :form_class, "flex flex-col"
    set :slot_class, nil
    set :button_text, "Créer mon compte"
    set :disable_button_text, "Création du compte…"
  end

  override Components.Password.ResetForm do
    set :form_class, "flex flex-col"
    set :slot_class, nil
    set :button_text, "Envoyer le lien"
    set :disable_button_text, "Envoi…"

    set :reset_flash_text,
        "Si cette adresse existe, un lien de réinitialisation vient de lui être envoyé."
  end

  override Components.Password.Input do
    set :field_class, "ta-field-wrap"
    set :label_class, "ta-field-label"
    set :input_class, nil
    set :input_class_with_error, "ta-field-input-error"
    set :identity_input_label, "Adresse e-mail"
    set :identity_input_placeholder, "prenom.nom@etablissement.cm"
    set :password_input_label, "Mot de passe"
    set :password_confirmation_input_label, "Confirmer le mot de passe"
    set :error_ul, "ta-error-list"
    set :error_li, nil
    set :input_debounce, 300
    set :submit_class, nil
  end

  override Components.Reset.Form do
    # The submit button text on this page (the `/password-reset/:token`
    # "set a new password" step) has no dedicated override key in
    # ash_authentication_phoenix — it falls back to the library's own
    # humanized action name. Everything else on this screen (heading,
    # eyebrow, subtitle, field labels, reassurance footer) is French.
    set :form_class, "flex flex-col"
    set :spacer_class, "mb-1"
    set :disable_button_text, "Réinitialisation…"
  end

  # --- best-effort "Rester connecté" checkbox --------------------------------
  #
  # Not wired to anything: the password strategy has no `remember_me`
  # add-on configured, so there's no session field to bind this to. It has
  # no `name`, so it's never submitted and can't affect the sign-in form.

  attr :form, :any, default: nil

  def remember_me_extra(assigns) do
    ~H"""
    <label class="ta-remember-row">
      <input type="checkbox" />
      <span>Rester connecté</span>
    </label>
    """
  end

  # --- "Nom et prénom" field, register-only ----------------------------------
  #
  # `User.name` is a plain nullable attribute (see
  # `TeacherAssistant.Accounts.User`) accepted by `:register_with_password`.
  # Rendered via `register_extra_component` (the same extension point as
  # `remember_me_extra` above), so it's real, bound, submitted form input —
  # boxed the same way as the email/password fields (`.ta-field-wrap` /
  # `.ta-field-label`, styled by `.ta-auth-paper input[type="text"]` in
  # `layouts/auth.html.heex`) — and it only ever renders on the register
  # form; sign-in has no `register_extra_component` set, so `/sign-in`
  # never shows it.

  attr :form, :any, default: nil

  def name_extra(assigns) do
    ~H"""
    <div class="ta-field-wrap">
      <label for={Phoenix.HTML.Form.input_id(@form, :name)} class="ta-field-label">
        Nom et prénom
      </label>
      <input
        type="text"
        name={Phoenix.HTML.Form.input_name(@form, :name)}
        id={Phoenix.HTML.Form.input_id(@form, :name)}
        value={Phoenix.HTML.Form.input_value(@form, :name)}
        placeholder="Prénom Nom"
        autocomplete="name"
        phx-debounce="300"
      />
    </div>
    """
  end

  # --- themed flashes (instead of hard-coded emerald/rose) ------------------

  override Components.Flash do
    set :message_class_info, """
    fixed top-3 right-3 w-80 sm:w-96 z-50 rounded-lg p-3 text-sm shadow-lg
    bg-success text-success-content
    """

    set :message_class_error, """
    fixed top-3 right-3 w-80 sm:w-96 z-50 rounded-lg p-3 text-sm shadow-lg
    bg-error text-error-content
    """
  end
end
