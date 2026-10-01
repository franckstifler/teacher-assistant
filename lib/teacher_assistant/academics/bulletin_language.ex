defmodule TeacherAssistant.Academics.BulletinLanguage do
  @moduledoc "Spec I5: a card follows its class's sub-system, or every card is bilingual."
  use Ash.Type.Enum, values: [:by_class, :bilingual]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:by_class), do: gettext("Suivre la classe (francophone / anglophone)")
  def label(:bilingual), do: gettext("Bilingue pour toutes les classes")
end
