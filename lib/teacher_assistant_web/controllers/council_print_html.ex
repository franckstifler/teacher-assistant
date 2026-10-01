defmodule TeacherAssistantWeb.CouncilPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{ConductWarning, Distinction, PassageDecision}

  embed_templates "council_print_html/*"

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp pct(nil), do: "—"
  defp pct(rate), do: "#{round(rate * 100)} %"

  defp date(nil), do: "—"
  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp distinction(nil), do: "—"
  defp distinction(value), do: Distinction.label(value)

  defp passage(%{passage: value}) when not is_nil(value), do: PassageDecision.label(value)
  defp passage(_outcome), do: "—"

  defp warning(nil), do: "—"
  defp warning(value), do: ConductWarning.label(value)
end
