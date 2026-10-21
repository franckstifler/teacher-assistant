defmodule TeacherAssistant.Academics.ReturnNoteReason do
  @moduledoc "Why the bursar lets a student back into class (Fees 2)."
  use Ash.Type.Enum, values: [:promise, :payment, :exemption]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:promise), do: gettext("Promesse de paiement")
  def label(:payment), do: gettext("Paiement reçu")
  def label(:exemption), do: gettext("Exonération")
end
