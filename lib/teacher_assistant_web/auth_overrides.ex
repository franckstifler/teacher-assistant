defmodule TeacherAssistantWeb.AuthOverrides do
  @moduledoc """
  Branding + layout overrides for the AshAuthentication.Phoenix pages
  (sign in, register, reset, magic link, confirm, sign out).

  These compose on top of `AshAuthentication.Phoenix.Overrides.DaisyUI`
  (declared after it in the router), so we only set the keys we want to
  change: a full-screen chalkboard backdrop, a branded card, the wordmark
  banner, and friendlier toggle copy. Colors come from our daisyUI theme.
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

  @page_root "ta-auth-bg min-h-screen grid place-items-center p-4"
  @card "ta-board w-full max-w-md mx-auto px-6 py-8 sm:px-8"
  @form_heading "ta-display mt-1 mb-5 text-2xl font-bold text-base-content"

  # --- full-page backdrops --------------------------------------------------

  override SignInLive do
    set :root_class, @page_root
  end

  override MagicSignInLive do
    set :root_class, @page_root
  end

  override ResetLive do
    set :root_class, @page_root
  end

  override ConfirmLive do
    set :root_class, @page_root
  end

  override SignOutLive do
    set :root_class, @page_root
  end

  # --- the branded card -----------------------------------------------------

  override Components.SignIn do
    set :root_class, @card
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "text-error text-center text-sm mt-2"
    set :strategy_display_order, :forms_first
  end

  override Components.Reset do
    set :root_class, @card
    set :strategy_class, "w-full"
  end

  override Components.Confirm do
    set :root_class, @card
    set :strategy_class, "w-full"
  end

  override Components.SignOut do
    set :root_class, @card
    set :h2_class, "#{@form_heading} text-center"
    set :h2_text, "See you soon"
    set :info_text, "Are you sure you want to sign out?"
    set :info_text_class, "text-sm text-base-content/65 mb-4 text-center"
    set :button_text, "Sign out"
    set :button_class, "btn btn-primary btn-block"
  end

  # --- wordmark banner (replaces the Ash logo) ------------------------------

  override Components.Banner do
    set :root_class, "w-full flex justify-center pb-3"
    set :href_url, "/"
    set :href_class, "ta-display text-2xl font-bold text-base-content tracking-tight"
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Teacher Assistant"
    set :text_class, "text-center"
  end

  # --- password: friendlier toggle copy + headings --------------------------

  override Components.Password do
    set :sign_in_toggle_text, "Already have an account? Sign in"
    set :register_toggle_text, "New here? Create an account"
    set :reset_toggle_text, "Forgot your password?"
    set :show_first, :sign_in
  end

  override Components.Password.SignInForm do
    set :label_class, "#{@form_heading} text-center"
    set :button_text, "Sign in"
  end

  override Components.Password.RegisterForm do
    set :label_class, "#{@form_heading} text-center"
    set :button_text, "Create account"
  end

  override Components.Password.ResetForm do
    set :label_class, "#{@form_heading} text-center"
  end

  override Components.MagicLink do
    set :label_class, "#{@form_heading} text-center"
  end

  override Components.Reset.Form do
    set :label_class, "#{@form_heading} text-center"
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
