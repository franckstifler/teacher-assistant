defmodule TeacherAssistantWeb.StatisticsPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.OfficialHeaderComponents, only: [official_header: 1]

  embed_templates "statistics_print_html/*"

  defp period_label({:sequence, seq}), do: gettext("Séquence %{n}", n: seq.number)
  defp period_label({:trimester, term}), do: gettext("Trimestre %{n}", n: term.position)
  defp period_label({:annual, _}), do: gettext("Année")

  defp source_line(_rows, {:sequence, _}), do: gettext("Chiffres des notes saisies")

  defp source_line(rows, _period) do
    sources = for r <- rows, r.class_label == nil, do: r.source

    cond do
      Enum.all?(sources, &(&1 == :published)) ->
        gettext("Chiffres des bulletins publiés")

      Enum.all?(sources, &(&1 == :live)) ->
        gettext("Chiffres provisoires (bulletins non publiés)")

      true ->
        gettext("Chiffres en partie provisoires (certains bulletins ne sont pas publiés)")
    end
  end

  defp fmt(nil), do: "—"

  defp fmt(%Decimal{} = d),
    do: d |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp short(nil), do: "—"

  defp short(%Decimal{} = d),
    do:
      d
      |> Decimal.round(1)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

  defp pct(nil), do: "—"
  defp pct(rate), do: "#{round(rate * 100)} %"

  defp mentions_text([]), do: "—"

  defp mentions_text(mentions),
    do: Enum.map_join(mentions, " · ", fn {label, n} -> "#{label} ×#{n}" end)

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
