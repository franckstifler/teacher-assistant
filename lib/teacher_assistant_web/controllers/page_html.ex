defmodule TeacherAssistantWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.

  The landing (`home`) speaks to schools only (UI review 2026-10): it walks a
  school day role by role with real screens of the demo school, in the app's
  « Tableau, affiné » look, and follows the visitor's theme.
  """
  use TeacherAssistantWeb, :html

  embed_templates "page_html/*"

  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :eager, :boolean, default: false

  @doc "A phone screen in a device frame (captures are 780×1688)."
  def phone_shot(assigns) do
    ~H"""
    <div class={["ta-device", @class]}>
      <img
        src={@src}
        alt={@alt}
        width="390"
        height="844"
        loading={if @eager, do: "eager", else: "lazy"}
        decoding="async"
      />
    </div>
    """
  end

  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :width, :integer, default: 1920
  attr :height, :integer, default: 1200
  attr :class, :any, default: nil
  attr :eager, :boolean, default: false

  attr :from, :atom,
    values: [nil, :sm, :md],
    default: nil,
    doc: "the breakpoint the shot is shown from; below it the browser fetches a blank pixel"

  @doc "A desktop screen in a plain window frame."
  def window_shot(assigns) do
    ~H"""
    <div class={["ta-window", @class]}>
      <picture>
        <source :if={@from} media={narrower_than(@from)} srcset={blank_pixel()} />
        <img
          src={@src}
          alt={@alt}
          width={@width}
          height={@height}
          loading={if @eager, do: "eager", else: "lazy"}
          decoding="async"
        />
      </picture>
    </div>
    """
  end

  # Tailwind's sm (40rem) and md (48rem), minus a hair so the two never overlap.
  defp narrower_than(:sm), do: "(max-width: 39.99rem)"
  defp narrower_than(:md), do: "(max-width: 47.99rem)"

  # A transparent 1×1 GIF: a hidden <img> is still downloaded, its <source> is not.
  defp blank_pixel,
    do: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

  attr :items, :list, required: true

  @doc "A short list of facts, each with a check."
  def checks(assigns) do
    ~H"""
    <ul class="mt-5 flex flex-col gap-2.5">
      <li :for={item <- @items} class="flex gap-3 text-[0.95rem] leading-snug">
        <.icon name="hero-check-circle" class="mt-0.5 size-5 flex-none text-primary" />
        <span>{item}</span>
      </li>
    </ul>
    """
  end

  @doc "The role-by-role walk through a school day."
  def day_steps do
    [
      %{
        id: "appel",
        time: "07:30",
        role: gettext("Enseignant"),
        title: gettext("L'appel en un geste, depuis le téléphone"),
        text:
          gettext(
            "Présent, absent, en retard : un geste par élève, et l'appel est enregistré avant la fin du cours. L'enseignant retrouve sa journée de cours, et les appels oubliés lui sont rappelés."
          ),
        points: [
          gettext("La journée de cours en un coup d'œil"),
          gettext("Les appels en retard signalés à l'enseignant"),
          gettext("Notes et appel au même endroit")
        ],
        shots: [
          {"/images/landing/roll-call.webp",
           gettext("L'appel de la 5e A sur téléphone : présents, absents et retards")},
          {"/images/landing/teacher-today.webp",
           gettext("La journée d'une enseignante : cours, appels à faire, notes à saisir")}
        ]
      },
      %{
        id: "vie-scolaire",
        time: "09:00",
        role: gettext("Surveillant général"),
        title: gettext("La vie scolaire remonte toute seule"),
        text:
          gettext(
            "Appels non faits, absents, retards et absences à justifier, classe par classe. Le surveillant général relance un appel manquant en un geste, enregistre les justificatifs et sait quels parents prévenir."
          ),
        points: [
          gettext("Appels manquants relancés en un geste"),
          gettext("Absences justifiées ou non, cumulées par séquence"),
          gettext("Conduite, sanctions et parents à prévenir")
        ],
        shots: [
          {"/images/landing/surveillant-day.webp",
           gettext("La journée du surveillant général : appels faits, absents, retards")}
        ]
      },
      %{
        id: "notes",
        time: "14:00",
        role: gettext("Enseignant"),
        title: gettext("Des notes saisies au fil de la séquence"),
        text:
          gettext(
            "Chaque note est enregistrée dès que l'enseignant quitte la case. Absences justifiées ou non, évaluations notées sur 20 ou sur un autre barème : les moyennes et les rangs se calculent seuls."
          ),
        points: [
          gettext("Saisie ouverte jusqu'à la date de clôture de la séquence"),
          gettext("Corrections de notes validées par l'administration"),
          gettext("Résultats de la classe par séquence")
        ],
        shots: [
          {"/images/landing/marks.webp",
           gettext("La saisie des notes d'une interrogation en 1re D")}
        ]
      },
      %{
        id: "suivi",
        time: "16:00",
        role: gettext("Censeur"),
        title: gettext("Le censeur relance avant la clôture, pas après"),
        text:
          gettext(
            "Qui a fini, qui est en retard, matière par matière et classe par classe. Le censeur voit la saisie avancer et relance les enseignants pendant qu'il en est encore temps."
          ),
        points: [
          gettext("Avancement de la saisie par classe et par matière"),
          gettext("Relance des enseignants en retard"),
          gettext("Emploi du temps des classes, conflits signalés")
        ],
        shots: [
          {"/images/landing/censeur-suivi.webp",
           gettext("Le suivi de la saisie des notes de la séquence 1 par le censeur")}
        ]
      }
    ]
  end

  @doc "What each role finds in its space (the phone tab bar of each)."
  def roles do
    [
      %{
        icon: "hero-building-library",
        title: gettext("Proviseur"),
        text:
          gettext(
            "La vue d'ensemble : ce qui bloque, par ordre d'urgence, la saisie de chaque classe et les décisions à prendre."
          ),
        tabs: [gettext("Accueil"), gettext("Classes"), gettext("Élèves"), gettext("Bulletins")]
      },
      %{
        icon: "hero-chart-bar-square",
        title: gettext("Censeur"),
        text:
          gettext(
            "Le suivi pédagogique : saisie des notes, emplois du temps, conseils de classe et bulletins."
          ),
        tabs: [
          gettext("Suivi"),
          gettext("Emploi du temps"),
          gettext("Classes"),
          gettext("Bulletins")
        ]
      },
      %{
        icon: "hero-clipboard-document-check",
        title: gettext("Surveillant général"),
        text:
          gettext(
            "La journée de l'établissement : appels, absences à justifier, conduite et sanctions."
          ),
        tabs: [gettext("Journée"), gettext("Absences"), gettext("Élèves"), gettext("Sanctions")]
      },
      %{
        icon: "hero-academic-cap",
        title: gettext("Enseignant"),
        text:
          gettext(
            "Ses cours du jour, l'appel, les notes de ses classes et son emploi du temps — rien de plus."
          ),
        tabs: [
          gettext("Aujourd'hui"),
          gettext("Mes cours"),
          gettext("Notes"),
          gettext("Emploi du temps")
        ]
      }
    ]
  end

  @doc "The rest of the toolbox, one line each."
  def more_features do
    [
      %{
        icon: "hero-table-cells",
        title: gettext("Emplois du temps"),
        text:
          gettext(
            "Grille par classe et par enseignant, quotas horaires par matière, conflits signalés, impression."
          )
      },
      %{
        icon: "hero-user-group",
        title: gettext("Conseils de classe"),
        text:
          gettext("Préparation, appréciations et décisions de passage, procès-verbal imprimable.")
      },
      %{
        icon: "hero-identification",
        title: gettext("Photos et cartes scolaires"),
        text:
          gettext(
            "Photos des élèves prises en classe, cartes scolaires imprimées à 10 par feuille A4."
          )
      },
      %{
        icon: "hero-banknotes",
        title: gettext("Frais de scolarité"),
        text:
          gettext(
            "Tranches par classe, paiements en espèces, Mobile Money ou virement, soldes par élève."
          )
      },
      %{
        icon: "hero-calendar-days",
        title: gettext("Calendrier scolaire"),
        text:
          gettext("Année, séquences et trimestres, congés et jours fériés de l'établissement.")
      },
      %{
        icon: "hero-arrow-up-tray",
        title: gettext("Import des listes"),
        text:
          gettext(
            "Collez la liste d'une classe depuis votre tableur : chaque ligne est vérifiée avant l'import."
          )
      },
      %{
        icon: "hero-device-phone-mobile",
        title: gettext("Comptes par téléphone"),
        text:
          gettext(
            "L'équipe se connecte avec son numéro : pas besoin d'adresse e-mail pour commencer."
          )
      },
      %{
        icon: "hero-bell",
        title: gettext("Notifications"),
        text:
          gettext(
            "Relances, corrections décidées, bulletins publiés : chacun est prévenu de ce qui le concerne."
          )
      }
    ]
  end

  @doc "How Cameroon's system is built in, not translated."
  def terrain do
    [
      %{
        title: gettext("Les deux sous-systèmes"),
        text:
          gettext(
            "Francophone et anglophone, avec leurs niveaux et leurs séries, dans une interface en français ou en anglais."
          )
      },
      %{
        title: gettext("Séquences et trimestres"),
        text:
          gettext(
            "Six séquences, trois trimestres, dates de clôture de la saisie et moyennes conformes aux usages."
          )
      },
      %{
        title: gettext("Coefficients et appréciations"),
        text:
          gettext(
            "Coefficients par niveau et par série, barème d'appréciations et distinctions de l'établissement."
          )
      },
      %{
        title: gettext("Bulletins imprimables"),
        text:
          gettext(
            "En-tête officiel, cachet et signature, pensés pour l'impression en noir et blanc."
          )
      },
      %{
        title: gettext("D'abord le téléphone"),
        text:
          gettext(
            "Chaque écran est conçu pour un téléphone et des pages légères ; l'ordinateur reste là pour l'administration."
          )
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
            "Le chef d'établissement crée son compte et renseigne l'identité de l'établissement."
          )
      },
      %{
        title: gettext("Configurez l'année"),
        text:
          gettext(
            "Un assistant guide l'année scolaire, les classes, les matières et les coefficients."
          )
      },
      %{
        title: gettext("Invitez l'équipe"),
        text:
          gettext(
            "Chaque membre reçoit un compte à son numéro de téléphone, avec le rôle qui est le sien."
          )
      }
    ]
  end

  @doc "Frequent questions, answered from what the app does today."
  def faq do
    [
      {gettext("Faut-il un ordinateur ?"),
       gettext(
         "Non. L'appel, les notes et le suivi se font sur téléphone. Un ordinateur et une imprimante servent surtout à imprimer les bulletins, les emplois du temps et les cartes scolaires."
       )},
      {gettext("Les enseignants doivent-ils avoir une adresse e-mail ?"),
       gettext(
         "Non. L'établissement crée leur compte avec leur numéro de téléphone et un mot de passe temporaire ; ils choisissent ensuite le leur."
       )},
      {gettext("Qui voit quoi ?"),
       gettext(
         "Chacun voit ce que son rôle lui permet : un enseignant voit ses classes, le surveillant général la vie scolaire, l'administration l'ensemble. Les données d'un établissement ne sont visibles que par ses membres."
       )},
      {gettext("Les établissements anglophones sont-ils pris en charge ?"),
       gettext(
         "Oui. Le sous-système anglophone a ses propres niveaux, et l'application se lit en français ou en anglais."
       )}
    ]
  end
end
