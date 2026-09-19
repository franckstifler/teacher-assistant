defmodule TeacherAssistant.Academics.PaymentMethod do
  use Ash.Type.Enum,
    values: [:cash, :mobile_money, :bank_transfer, :other]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:cash), do: gettext("Espèces")
  def label(:mobile_money), do: gettext("Mobile money")
  def label(:bank_transfer), do: gettext("Virement bancaire")
  def label(:other), do: gettext("Autre")
end
