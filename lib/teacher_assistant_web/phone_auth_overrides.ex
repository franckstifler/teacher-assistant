defmodule TeacherAssistantWeb.PhoneAuthOverrides do
  @moduledoc """
  Overrides applied only to the phone strategy's form on `/sign-in`
  (placed before `TeacherAssistantWeb.AuthOverrides`, so these keys win).
  """
  use AshAuthentication.Phoenix.Overrides
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias AshAuthentication.Phoenix.Components

  override Components.Password.Input do
    set :identity_input_label, dgettext_noop("auth", "Numéro de téléphone")
    set :identity_input_placeholder, "6XX XX XX XX"
  end
end
