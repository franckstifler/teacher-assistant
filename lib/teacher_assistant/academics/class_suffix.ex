defmodule TeacherAssistant.Academics.ClassSuffix do
  @moduledoc "Spec KLM5: how a school tells classes of one level apart (6e A, 6e B or 6e 1, 6e 2)."
  use Ash.Type.Enum, values: [:letters, :numbers]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:letters), do: gettext("Lettres (6e A, 6e B)")
  def label(:numbers), do: gettext("Numéros (6e 1, 6e 2)")
end
