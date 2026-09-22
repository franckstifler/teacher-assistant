defmodule TeacherAssistant.Accounts.Emails do
  @moduledoc "Builds Swoosh emails for account/invitation flows. Delivery is via TeacherAssistant.Mailer."
  import Swoosh.Email
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def school_invitation(email, school_name, accept_url) do
    base()
    |> to(to_string(email))
    |> subject(gettext("Invitation à rejoindre %{school}", school: school_name))
    |> text_body(
      gettext(
        "Vous avez été invité(e) à rejoindre %{school} sur Teacher Assistant.\n\nAcceptez l'invitation ici : %{url}",
        school: school_name,
        url: accept_url
      )
    )
    |> html_body(
      gettext(
        "<p>Vous avez été invité(e) à rejoindre <strong>%{school}</strong>.</p><p><a href=\"%{url}\">Accepter l'invitation</a></p>",
        school: school_name,
        url: accept_url
      )
    )
  end

  def password_reset(user, reset_url) do
    base()
    |> to(to_string(user.email))
    |> subject(gettext("Réinitialisation de votre mot de passe"))
    |> text_body(gettext("Réinitialisez votre mot de passe ici : %{url}", url: reset_url))
    |> html_body(gettext("<p><a href=\"%{url}\">Réinitialiser mon mot de passe</a></p>", url: reset_url))
  end

  def magic_link(user, magic_url) do
    base()
    |> to(to_string(user.email))
    |> subject(gettext("Votre lien de connexion"))
    |> text_body(gettext("Connectez-vous ici : %{url}", url: magic_url))
    |> html_body(gettext("<p><a href=\"%{url}\">Se connecter</a></p>", url: magic_url))
  end

  defp base do
    new() |> from(from_address())
  end

  defp from_address do
    Application.get_env(:teacher_assistant, __MODULE__)[:from] ||
      {"Teacher Assistant", "no-reply@teacherassistant.cm"}
  end
end
