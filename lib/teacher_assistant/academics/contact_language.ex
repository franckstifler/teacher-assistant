defmodule TeacherAssistant.Academics.ContactLanguage do
  @moduledoc "Spec KLM1: the language a guardian is written to in."
  use Ash.Type.Enum, values: [:fr, :en]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:fr), do: gettext("Français")
  def label(:en), do: gettext("Anglais")
end
