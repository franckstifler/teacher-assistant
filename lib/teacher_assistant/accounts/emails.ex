defmodule TeacherAssistant.Accounts.Emails do
  @moduledoc "Builds Swoosh emails for account/invitation flows and operator alerts. Delivery is via TeacherAssistant.Mailer."
  import Swoosh.Email
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def school_invitation(email, school_name, accept_url) do
    base()
    |> to(to_string(email))
    |> subject(gettext("Invitation à rejoindre %{school}", school: school_name))
    |> text_body(
      gettext(
        "Vous avez été invité(e) à rejoindre %{school} sur Scolaka.\n\nAcceptez l'invitation ici : %{url}",
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
    |> html_body(
      gettext("<p><a href=\"%{url}\">Réinitialiser mon mot de passe</a></p>", url: reset_url)
    )
  end

  def magic_link(user, magic_url) do
    base()
    |> to(to_string(user.email))
    |> subject(gettext("Votre lien de connexion"))
    |> text_body(gettext("Connectez-vous ici : %{url}", url: magic_url))
    |> html_body(gettext("<p><a href=\"%{url}\">Se connecter</a></p>", url: magic_url))
  end

  @doc """
  To an operator: an unhandled error stored in `/admin/errors`, new or back after being
  resolved (`TeacherAssistant.Workers.ErrorAlert`). Kind, place, time and the link
  only: the message may hold a pupil's name or mark, so it stays in the tracker (spec
  audit follow-ups A6, as the Telegram alert).
  """
  def error_alert(user, error, reopened?, url) do
    source = "#{error.source_function} (#{error.source_line})"
    kind = short_kind(error.kind)
    at = TeacherAssistantWeb.Dates.short_datetime(error.last_occurrence_at)

    subject =
      if reopened?,
        do: gettext("Erreur revenue : %{kind}", kind: kind),
        else: gettext("Nouvelle erreur : %{kind}", kind: kind)

    html = &(&1 |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string())

    base()
    |> to(to_string(user.email))
    |> subject(subject)
    |> text_body(
      gettext("%{kind}\n\nÀ %{source}\nLe %{at}\n\nVoir l'erreur : %{url}",
        kind: kind,
        source: source,
        at: at,
        url: url
      )
    )
    |> html_body(
      gettext(
        "<p><strong>%{kind}</strong></p><p>À <code>%{source}</code><br />Le %{at}</p><p><a href=\"%{url}\">Voir l'erreur</a></p>",
        kind: html.(kind),
        source: html.(source),
        at: html.(at),
        url: html.(url)
      )
    )
  end

  defp short_kind("Elixir." <> kind), do: kind
  defp short_kind(kind), do: kind

  defp base do
    new() |> from(from_address())
  end

  defp from_address do
    Application.get_env(:teacher_assistant, __MODULE__)[:from] ||
      {"Scolaka", "no-reply@scolaka.com"}
  end
end
