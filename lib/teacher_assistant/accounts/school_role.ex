defmodule TeacherAssistant.Accounts.SchoolRole do
  @moduledoc "Bilingual display labels for school roles (Décret 2001/041, doc 05 §1)."

  use Ash.Type.Enum,
    values: [
      :head,
      :vice_principal,
      :discipline_master,
      :bursar,
      :hod,
      :teacher,
      :guidance_counsellor,
      :librarian
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc """
  The roles that count for an authority axis — the single definition used by
  `TeacherAssistant.Accounts.Checks.SchoolRole` (policies) and navigation gates.
  `:member` is any role; the membership itself must be active.
  """
  def axis(:member), do: values()
  def axis(:admin), do: [:head, :vice_principal]
  def axis(:head), do: [:head]
  def axis(:conduct), do: [:head, :vice_principal, :discipline_master]
  def axis(:fees), do: [:head, :vice_principal, :bursar]

  def label(:head), do: gettext("Chef d'établissement")
  def label(:vice_principal), do: gettext("Censeur")
  def label(:discipline_master), do: gettext("Surveillant général")
  def label(:bursar), do: gettext("Intendant")
  def label(:hod), do: gettext("Animateur pédagogique")
  def label(:teacher), do: gettext("Enseignant")
  def label(:guidance_counsellor), do: gettext("Conseiller d'orientation")
  def label(:librarian), do: gettext("Documentaliste")

  @doc """
  Spec KLM7: what each role may do, in plain words, for the read-only rights
  matrix. `axis` is the policy axis that grants the right; `resource` is one
  resource whose policies use that axis (checked by a test); `notes` carries
  row-level rules (a teacher's own courses, a form master's class).
  """
  def rights do
    alias TeacherAssistant.Academics, as: A
    alias TeacherAssistant.Accounts, as: Acc

    [
      %{key: :marks, label: gettext("Saisir les notes"), axis: :admin, resource: A.Mark,
        notes: %{teacher: gettext("ses cours"), hod: gettext("ses cours")}},
      %{key: :corrections, label: gettext("Valider les corrections de notes"), axis: :admin, resource: A.MarkCorrection,
        notes: %{teacher: gettext("demander, pour ses cours")}},
      %{key: :discipline, label: gettext("Gérer la discipline et la conduite"), axis: :conduct, resource: A.SanctionEntry,
        notes: %{teacher: gettext("sa classe, en lecture (professeur principal)")}},
      %{key: :fees, label: gettext("Frais et paiements"), axis: :fees, resource: A.Payment, notes: %{}},
      %{key: :settings, label: gettext("Paramètres de l'école"), axis: :admin, resource: Acc.SchoolProfile,
        notes: %{discipline_master: gettext("assiduité et discipline")}},
      %{key: :members, label: gettext("Membres et invitations"), axis: :head, resource: Acc.SchoolInvitation, notes: %{}},
      %{key: :timetable, label: gettext("Emploi du temps"), axis: :admin, resource: A.TimetableSlot, notes: %{}},
      %{key: :bulletins, label: gettext("Bulletins et conseils de classe"), axis: :admin, resource: A.ClassCouncil,
        notes: %{teacher: gettext("sa classe (professeur principal)")}},
      %{key: :assignments, label: gettext("Affectations"), axis: :admin, resource: A.TeachingContext, notes: %{}}
    ]
  end

  @doc "A matrix cell: `{:note, text}` for a row rule, else `:yes` when the role is on the axis, else `:no`."
  def cell(%{notes: notes, axis: axis}, role) do
    cond do
      Map.has_key?(notes, role) -> {:note, notes[role]}
      role in axis(axis) -> :yes
      true -> :no
    end
  end
end
