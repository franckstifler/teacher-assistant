defmodule TeacherAssistantWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.

  The landing (`home`) speaks to schools only: one sequence from the roll call to
  the bulletin, role by role, in the app's « Tableau, affiné » look. The screens in
  the hero are drawn in HTML with the theme's tokens (decorative, aria-hidden), so
  they follow the visitor's theme and never go stale with the UI. The bulletin and
  the receipt are real prints from the demo school (priv/static/images/landing),
  because the printed paper is what a school judges.
  """
  use TeacherAssistantWeb, :html

  embed_templates "page_html/*"

  attr :items, :list, required: true
  attr :class, :any, default: nil

  @doc "A short list of facts, each with a check."
  def checks(assigns) do
    ~H"""
    <ul class={["flex flex-col gap-2.5", @class]}>
      <li :for={item <- @items} class="flex gap-3 text-[0.95rem] leading-snug">
        <.icon name="hero-check" class="mt-0.5 size-5 flex-none text-primary" />
        <span>{item}</span>
      </li>
    </ul>
    """
  end

  @doc "The landing's headline (also the start of the meta description)."
  def headline, do: gettext("Tout l'établissement, sur le téléphone de chacun.")

  @doc "The hero's lede (also the rest of the meta description)."
  def lede do
    gettext(
      "L'appel, les notes, les bulletins et les frais, avec un espace pour chaque membre de l'équipe. Les bulletins sont prêts le soir du conseil de classe."
    )
  end

  @doc "The WhatsApp number shown on the landing, or nil to hide its links."
  def contact_whatsapp, do: contact(:whatsapp)

  @doc "The contact e-mail shown on the landing, or nil to hide it."
  def contact_email, do: contact(:email)

  defp contact(key) do
    case Application.get_env(:teacher_assistant, :contact, [])[key] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  @doc "A wa.me link to the contact number with `message` already typed."
  def whatsapp_url(message) do
    digits = String.replace(contact_whatsapp(), ~r/\D/, "")
    "https://wa.me/#{digits}?text=" <> URI.encode(message, &URI.char_unreserved?/1)
  end

  @doc "The message a visitor sends to ask for a demonstration."
  def demo_message,
    do: gettext("Bonjour, je souhaite une démonstration de Scolaka pour mon établissement.")

  @doc "The message a visitor sends with a question."
  def question_message, do: gettext("Bonjour, j'ai une question sur Scolaka.")

  attr :class, :any, default: nil

  @doc "« Une question ? » with the WhatsApp and e-mail links (nothing when neither is set)."
  def contact_line(assigns) do
    ~H"""
    <p
      :if={contact_whatsapp() || contact_email()}
      class={["ta-landing__lead text-[0.95rem] leading-relaxed", @class]}
      phx-no-format
    >
      {gettext("Une question ?")}
      <a
        :if={contact_whatsapp()}
        href={whatsapp_url(question_message())}
        target="_blank"
        rel="noopener"
        class="font-semibold text-primary underline underline-offset-4"
      >{gettext("Écrivez-nous sur WhatsApp")}</a>
      <span :if={contact_whatsapp() && contact_email()}>{gettext("ou à")}</span>
      <a
        :if={contact_email()}
        href={"mailto:" <> contact_email()}
        class="font-semibold text-primary underline underline-offset-4"
      >{contact_email()}</a>
    </p>
    """
  end

  @doc "The current locale, for the FR · EN switch."
  def locale, do: Gettext.get_locale(TeacherAssistantWeb.Gettext)

  attr :current_user, :any, default: nil

  @doc "The public pages' footer (embedded from page_html/site_footer.html.heex)."
  def site_footer(assigns)

  @doc "The landing's sections, for the header nav (desktop) and its menu (phone)."
  def sections do
    [
      {"#sequence", gettext("Comment ça marche")},
      {"#frais", gettext("Frais")},
      {"#inclus", gettext("Modules")},
      {"#tarif", gettext("Tarif")},
      {"#questions", gettext("Questions")}
    ]
  end

  @doc "The hero window: how far each level's marks are entered (a drawing)."
  def entry_bars do
    [
      {gettext("Niveau 1"), 82},
      {gettext("Niveau 2"), 64},
      {gettext("Niveau 3"), 91},
      {gettext("2nde"), 48},
      {gettext("1ère"), 73},
      {gettext("Terminale"), 100}
    ]
  end

  @doc "The hero phone: a teacher's next lessons (a drawing)."
  def lessons do
    [
      {"07:30", gettext("Anglais · 2nde"), :done},
      {"08:20", gettext("Anglais · Niv. 1"), :done},
      {"11:05", gettext("Anglais · Niv. 2"), :upcoming},
      {"11:55", gettext("Trav. manuels"), :upcoming}
    ]
  end

  @doc "« 82 % » in French, « 82% » in English."
  def percent(value), do: gettext("%{value} %", value: value)

  @doc "One sequence, from the roll call to the bulletin."
  def sequence_steps do
    [
      %{
        role: gettext("Enseignant"),
        title: gettext("L'appel en début de cours"),
        text:
          gettext(
            "Tout le monde est présent par défaut : on touche seulement les absents et les retards. Un cours groupé de cinq classes se fait en un seul appel."
          ),
        proof: gettext("Un seul appel par cours groupé")
      },
      %{
        role: gettext("Enseignant"),
        title: gettext("Les notes saisies en classe"),
        text:
          gettext(
            "Un pavé numérique pensé pour le téléphone, une note par élève, enregistrée aussitôt. Absent ou absence justifiée en une touche."
          ),
        proof: gettext("Enregistrement élève par élève")
      },
      %{
        role: gettext("Censeur"),
        title: gettext("Le suivi au jour le jour"),
        text:
          gettext(
            "Avancement par enseignant, par classe et par matière. Une relance groupée pour tous ceux qui n'ont pas commencé, bien avant la clôture."
          ),
        proof: gettext("Relance en un clic")
      },
      %{
        role: gettext("Proviseur"),
        title: gettext("Le conseil, puis les bulletins"),
        text:
          gettext(
            "Conseils de classe planifiés, bulletins calculés, publiés et imprimés le soir même."
          ),
        proof: gettext("Format officiel, code QR")
      }
    ]
  end

  @doc "The pilot band: every module the pilot includes."
  def pilot_modules do
    [
      gettext("Appel"),
      gettext("Notes"),
      gettext("Bulletins"),
      gettext("Frais"),
      gettext("Emploi du temps"),
      gettext("Discipline"),
      gettext("Cartes d'élève")
    ]
  end

  @doc "Everything the pilot includes, module by module."
  def modules do
    [
      %{
        icon: "hero-clipboard-document-check",
        title: gettext("Appel et absences"),
        text:
          gettext(
            "L'appel à chaque cours, les absences à justifier, les heures d'absence par élève. Une feuille d'appel imprimée pour les classes sans téléphone, saisie ensuite par le surveillant."
          )
      },
      %{
        icon: "hero-pencil-square",
        title: gettext("Notes et séquences"),
        text:
          gettext(
            "La saisie au téléphone, le suivi de l'avancement par le censeur et les corrections validées avant d'arriver au bulletin."
          )
      },
      %{
        icon: "hero-document-text",
        title: gettext("Bulletins et conseils"),
        text:
          gettext(
            "Coefficients, rangs et appréciations, conseils de classe, puis le passage en classe supérieure en fin d'année."
          )
      },
      %{
        icon: "hero-banknotes",
        title: gettext("Frais et reçus"),
        text:
          gettext(
            "Montants par niveau, tranches et échéances, reçus numérotés vérifiables, retards de paiement classe par classe."
          )
      },
      %{
        icon: "hero-calendar-days",
        title: gettext("Emploi du temps"),
        text:
          gettext(
            "Construit par le censeur avec les salles et les disponibilités des enseignants, imprimé par classe ou par enseignant."
          )
      },
      %{
        icon: "hero-scale",
        title: gettext("Discipline"),
        text:
          gettext(
            "La conduite et les sanctions de chaque élève, à portée du surveillant général et du proviseur."
          )
      },
      %{
        icon: "hero-identification",
        title: gettext("Élèves et cartes"),
        text:
          gettext(
            "Les listes importées depuis Excel, les photos, les cartes scolaires avec code QR et les photos pour les examens officiels."
          )
      },
      %{
        icon: "hero-printer",
        title: gettext("Impressions"),
        text:
          gettext(
            "Listes de classe, emplois du temps, bulletins, reçus et lettres aux familles, prêts à imprimer."
          )
      }
    ]
  end

  @doc "What each role finds in its space (the phone tab bar of each)."
  def roles do
    [
      %{
        title: gettext("Enseignant"),
        text:
          gettext(
            "Sa journée de cours, l'appel, la saisie des notes et les résultats de ses classes."
          ),
        tabs: [gettext("Ma journée"), gettext("Mes cours"), gettext("EDT")]
      },
      %{
        title: gettext("Censeur"),
        text:
          gettext(
            "L'avancement de la saisie, les relances, l'emploi du temps et la validation des corrections."
          ),
        tabs: [gettext("Suivi"), gettext("EDT"), gettext("Classes"), gettext("Bulletins")]
      },
      %{
        title: gettext("Surveillant général"),
        text:
          gettext(
            "Les appels du jour, les absences à justifier, la conduite et les familles à prévenir."
          ),
        tabs: [gettext("Journée"), gettext("Absences"), gettext("Élèves"), gettext("Sanctions")]
      },
      %{
        title: gettext("Proviseur et intendant"),
        text:
          gettext(
            "Le pilotage de l'établissement, les bulletins, l'équipe, les frais et les reçus."
          ),
        tabs: [gettext("Accueil"), gettext("Classes"), gettext("Bulletins"), gettext("Frais")]
      }
    ]
  end

  @doc "Getting started, in order."
  def start_steps do
    [
      %{
        title: gettext("Inscrivez l'établissement"),
        text:
          gettext(
            "Le chef d'établissement crée le compte en quelques minutes ; nous vérifions l'établissement avant l'ouverture des appels et des notes."
          )
      },
      %{
        title: gettext("Importez classes et élèves"),
        text:
          gettext(
            "En collant vos listes depuis Excel : classes et élèves, puis matières et coefficients. Pendant la phase pilote, nous le faisons avec vous."
          )
      },
      %{
        title: gettext("Invitez l'équipe"),
        text:
          gettext(
            "Chaque membre se connecte avec son numéro de téléphone et un mot de passe provisoire remis par l'établissement."
          )
      }
    ]
  end

  @doc "The privacy page, part by part: only what the app does today."
  def privacy_sections do
    [
      %{
        id: "owner",
        title: gettext("Les données appartiennent à l'établissement"),
        paragraphs: [
          gettext(
            "Chaque établissement décide de ce qu'il saisit dans Scolaka. Nous gardons ces données pour lui : nous ne les vendons pas, ne les louons pas et ne les utilisons pas pour de la publicité."
          )
        ]
      },
      %{
        id: "kept",
        title: gettext("Ce que nous gardons"),
        paragraphs: [],
        items: [
          gettext(
            "Pour chaque membre de l'équipe : son nom, son numéro de téléphone, son adresse e-mail s'il en donne une, son rôle et la date de sa dernière connexion. Son mot de passe est gardé sous une forme chiffrée que personne ne peut relire."
          ),
          gettext(
            "Pour chaque élève : son nom, son sexe, son matricule, sa date et son lieu de naissance, sa photo, sa classe, ses notes, ses absences, sa conduite, ses sanctions et ses paiements de frais, ainsi que son numéro d'identification national si l'établissement le saisit."
          ),
          gettext(
            "Pour les parents et tuteurs : leur nom, leur lien avec l'élève, leurs numéros de téléphone, leur adresse e-mail et la langue dans laquelle les contacter."
          )
        ]
      },
      %{
        id: "seen",
        title: gettext("Qui peut les voir"),
        paragraphs: [
          gettext(
            "Seuls les membres d'un établissement voient ses données, et chacun selon son rôle : l'enseignant ses classes, le censeur la pédagogie, l'intendant les frais, le proviseur tout l'établissement."
          ),
          gettext(
            "Pour le support, l'équipe Scolaka peut ouvrir l'espace d'un membre ; chaque accès est limité à une heure et inscrit dans un journal, et ce qui est saisi pendant cet accès porte le nom de l'opérateur."
          ),
          gettext(
            "Les bulletins, reçus et cartes scolaires portent un code QR. Celui qui le scanne voit seulement de quoi vérifier que le document est authentique : l'établissement, l'élève, sa classe et ce que dit le document."
          )
        ]
      },
      %{
        id: "where",
        title: gettext("Où elles se trouvent"),
        paragraphs: [
          gettext(
            "Les données sont gardées sur un serveur loué à la société allemande Hetzner. Les pages passent par Cloudflare entre ce serveur et votre téléphone, et les e-mails de Scolaka (invitations, mot de passe oublié) sont envoyés par Brevo, qui reçoit pour cela l'adresse et le message."
          ),
          gettext(
            "Quand vous envoyez un reçu par WhatsApp, c'est votre téléphone qui l'envoie : Scolaka n'a pas accès à vos conversations."
          )
        ]
      },
      %{
        id: "cookies",
        title: gettext("Cookies"),
        paragraphs: [
          gettext(
            "Scolaka utilise un seul cookie, celui qui garde votre session ouverte et retient votre langue ; Cloudflare peut y ajouter un cookie technique de sécurité. Votre téléphone garde aussi le thème choisi, clair ou sombre. Il n'y a ni publicité ni outil de suivi."
          )
        ]
      }
    ]
  end

  @doc "Frequent questions, answered from what the app does today."
  def faq do
    [
      {gettext("Faut-il un ordinateur ?"),
       gettext(
         "Un smartphone suffit pour les enseignants et le surveillant général. Le proviseur et le censeur profitent d'un écran plus large pour l'emploi du temps et les bulletins."
       )},
      {gettext("Les enseignants ont-ils besoin d'une adresse e-mail ?"),
       gettext(
         "Un numéro de téléphone suffit. L'établissement leur remet un mot de passe provisoire ; ils peuvent ensuite choisir le leur."
       )},
      {gettext("Qui voit quoi ?"),
       gettext(
         "Chaque rôle voit ce qui le concerne : l'enseignant ses classes, le censeur la pédagogie, l'intendant les frais. Le proviseur voit tout. Les données d'un établissement ne sont visibles que par ses membres."
       )},
      {gettext("Et si le réseau est faible ?"),
       gettext(
         "L'application est légère : moins de 300 Ko au premier chargement, gardés ensuite par le téléphone, puis peu de données à chaque action. Elle a besoin du réseau pour enregistrer et ne fonctionne pas hors ligne. Pour une classe sans réseau, une feuille d'appel imprimée se remplit à la main et se saisit plus tard."
       )},
      {gettext("Les établissements anglophones sont-ils pris en charge ?"),
       gettext(
         "Oui : le sous-système anglophone a ses propres niveaux, ses bulletins s'impriment en anglais, et l'application se lit en français ou en anglais, au choix de chacun."
       )}
    ]
  end
end
