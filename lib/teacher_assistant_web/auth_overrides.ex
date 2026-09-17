defmodule TeacherAssistantWeb.AuthOverrides do
  @moduledoc """
  Branding + layout overrides for the AshAuthentication.Phoenix pages
  (sign in, register, reset, magic link, confirm, sign out).

  These compose on top of `AshAuthentication.Phoenix.Overrides.DaisyUI`
  (declared after it in the router), so we only set the keys we want to
  change.

  Sign in / register / reset / magic-link render inside the split-screen
  `Layouts.auth` layout (wired in the router), so their forms are flat —
  the layout supplies the chalkboard brand panel and the surface. Confirm
  and sign-out are not wrapped by that layout, so they keep a self-contained
  board card on the full-screen backdrop.

  The signature move is the field itself: a chalk-underline rule you write
  on (`.ta-field`) rather than a boxed input. Colors come from the theme.
  """
  use AshAuthentication.Phoenix.Overrides

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
  @field_label "block font-mono text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60 mb-1.5"

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
    set :authentication_error_container_class, "text-error text-sm mt-2"
    set :strategy_display_order, :forms_first
  end

  override Components.Reset do
    set :root_class, "w-full"
    set :strategy_class, "w-full"
  end

  override Components.Confirm do
    set :root_class, @card_standalone
    set :strategy_class, "w-full"
  end

  override Components.SignOut do
    set :root_class, @card_standalone
    set :h2_class, "#{@heading} text-center"
    set :h2_text, "See you soon"
    set :info_text, "Are you sure you want to sign out?"
    set :info_text_class, "text-sm text-base-content/65 mb-4 text-center"
    set :button_text, "Sign out"
    set :button_class, "btn btn-primary btn-block"
  end

  # --- wordmark banner: shown on the form only at mobile widths --------------
  # (on desktop the split-screen brand panel carries the wordmark)

  override Components.Banner do
    set :root_class, "w-full flex justify-start pb-6 lg:hidden"
    set :href_url, "/"
    set :href_class, "ta-display text-2xl font-semibold tracking-tight text-base-content"
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Teacher Assistant"
    set :text_class, ""
  end

  # --- password: headings, quiet toggle links, chalk-underline fields --------

  override Components.Password do
    set :toggler_class,
        "mt-6 inline-block text-sm text-info underline-offset-4 hover:underline"

    set :sign_in_toggle_text, "Already have an account? Sign in"
    set :register_toggle_text, "New here? Create an account"
    set :reset_toggle_text, "Forgot your password?"
    set :show_first, :sign_in
  end

  override Components.Password.SignInForm do
    set :label_class, @heading
    set :button_text, "Sign in"
  end

  override Components.Password.RegisterForm do
    set :label_class, @heading
    set :button_text, "Create account"
  end

  override Components.Password.ResetForm do
    set :label_class, @heading
  end

  override Components.Password.Input do
    set :field_class, "mb-4"
    set :label_class, @field_label
    set :input_class, "ta-field"
    set :input_class_with_error, "ta-field ta-field-error"
    set :submit_class, "btn btn-primary btn-block btn-lg mt-6"
  end

  override Components.MagicLink do
    set :label_class, @heading
  end

  override Components.Reset.Form do
    set :label_class, @heading
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
