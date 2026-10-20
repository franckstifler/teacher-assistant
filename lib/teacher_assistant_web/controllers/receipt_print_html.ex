defmodule TeacherAssistantWeb.ReceiptPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts.Phone
  alias TeacherAssistant.Academics.PaymentMethod
  alias TeacherAssistantWeb.{AmountInWords, Money}

  embed_templates "receipt_print_html/*"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp left(left) when left < 0,
    do: gettext("Trop-perçu : %{amount}", amount: Money.format_fcfa(-left))

  defp left(left), do: Money.format_fcfa(left)

  defp in_words(amount), do: AmountInWords.fr(amount) <> " " <> gettext("francs CFA")

  @doc """
  A `https://wa.me/<237…>?text=…` link sending the receipt summary to a guardian's
  phone, or nil for a number that is not a valid Cameroonian one.
  """
  def whatsapp_url(phone, message) do
    case Phone.normalize(phone) do
      {:ok, "+" <> digits} -> "https://wa.me/#{digits}?text=#{URI.encode_www_form(message)}"
      _ -> nil
    end
  end

  defp whatsapp_message(receipt, check_url) do
    p = receipt.payment

    gettext(
      "%{school} — Reçu n° %{number} du %{date} : %{amount} payés pour %{student} (%{class}). Reste à payer : %{left}. Vérifier : %{url}",
      school: receipt.school.name,
      number: p.number,
      date: date(p.paid_on),
      amount: Money.format_fcfa(p.amount),
      student: receipt.student.full_name,
      class: receipt.class_group.label,
      left: left(p.left_after),
      url: check_url
    )
  end
end
