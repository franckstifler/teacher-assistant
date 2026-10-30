defmodule TeacherAssistant.Academics.AbsenceHoursSource do
  @moduledoc """
  Where a class's bulletin absence hours come from (spec 2026-10-30): the roll call, or
  figures typed by hand per séquence or per trimester. One source per class, never both.
  """
  use Ash.Type.Enum, values: [:roll_call, :typed_per_sequence, :typed_per_term]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:roll_call), do: gettext("Calculées depuis l'appel")
  def label(:typed_per_sequence), do: gettext("Saisies à la main, par séquence")
  def label(:typed_per_term), do: gettext("Saisies à la main, par trimestre")
end
