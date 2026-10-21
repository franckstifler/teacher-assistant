defmodule TeacherAssistantWeb.ReceiptVerifyHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.ReturnNoteReason
  alias TeacherAssistantWeb.Money

  embed_templates "receipt_verify_html/*"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp left(left) when left < 0,
    do: gettext("Trop-perçu : %{amount}", amount: Money.format_fcfa(-left))

  defp left(left), do: Money.format_fcfa(left)
end
