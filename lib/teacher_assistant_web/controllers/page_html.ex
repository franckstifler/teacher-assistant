defmodule TeacherAssistantWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.

  The landing (`home`) speaks to schools only: one sequence from the roll call to
  the bulletin, role by role, in the app's « Tableau, affiné » look. Its pictures
  of the app are drawn in HTML with the theme's tokens (decorative, aria-hidden),
  so they follow the visitor's theme and never go stale with the UI.
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

  @doc "The current locale, for the FR · EN switch."
  def locale, do: Gettext.get_locale(TeacherAssistantWeb.Gettext)

  @doc "The landing's sections, for the header nav (desktop) and its menu (phone)."
  def sections do
    [
      {"#sequence", gettext("Comment ça marche")},
      {"#roles", gettext("Rôles")},
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

  @doc "The drawn bulletin's rows: subject, coefficient, mark."
  def bulletin_rows do
    [
      {gettext("Français"), 4, 13.5},
      {gettext("Anglais"), 3, 14.0},
      {gettext("Mathématiques"), 4, 11.25},
      {gettext("Économie familiale"), 5, 15.0},
      {gettext("Hygiène"), 2, 12.0},
      {gettext("Histoire-géo"), 2, 10.5},
      {gettext("ECM"), 1, 13.0},
      {gettext("EPS"), 1, 16.0}
    ]
  end

  @doc "A mark as printed: « 13,50 » in French, « 13.50 » in English."
  def mark(value) do
    text = :erlang.float_to_binary(value * 1.0, decimals: 2)
    if locale() == "fr", do: String.replace(text, ".", ","), else: text
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
        tabs: [gettext("Ma journée"), gettext("Mes cours"), gettext("Bulletins"), gettext("EDT")]
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
            "En collant vos listes depuis Excel : classes et élèves, puis matières et coefficients, réglés par l'établissement."
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
      {gettext("Les établissements anglophones sont-ils pris en charge ?"),
       gettext(
         "Oui : le sous-système anglophone a ses propres niveaux, ses bulletins s'impriment en anglais, et l'application se lit en français ou en anglais, au choix de chacun."
       )}
    ]
  end
end
