defmodule TeacherAssistantWeb.MarkSheetPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.BulletinPrintHTML, only: [tr: 2]

  alias TeacherAssistant.Organization

  embed_templates "mark_sheet_print_html/*"

  defp html_lang(:en), do: "en"
  defp html_lang(_), do: "fr"

  # « Séquence 2 », « Trimestre 1 (séquences 1 et 2) », in the class's language.
  defp period_title(lang, period), do: tr(lang, fn -> period_label(period) end)

  defp period_label({:sequence, seq}), do: gettext("Séquence %{n}", n: seq.number)

  defp period_label({:trimester, term}) do
    numbers = term.sequences |> Enum.map(& &1.number) |> Enum.sort()

    gettext("Trimestre %{n} (séquences %{a} et %{b})",
      n: term.position,
      a: List.first(numbers),
      b: List.last(numbers)
    )
  end

  # The subject's code (« MATH »), else the start of its name.
  defp abbreviation(%{code: code}) when is_binary(code) and code != "", do: code

  defp abbreviation(%{label: label}),
    do: label |> String.upcase() |> String.slice(0, 4)

  defp cell(%{cells: cells}, subject, seq), do: cells[{subject.context_id, seq.id}]

  defp cell_text({:mark, %Decimal{} = d}, lang) do
    str = d |> Decimal.normalize() |> Decimal.to_string(:normal)
    if lang == :en, do: str, else: String.replace(str, ".", ",")
  end

  defp cell_text(:absent, _lang), do: "Abs"
  defp cell_text(:exempt, _lang), do: "Disp"
  defp cell_text(_blank, _lang), do: "—"

  defp cell_class({:mark, _}), do: nil
  defp cell_class(:absent), do: "abs"
  defp cell_class(_), do: "empty"

  # Type size falls with the class size so a class fits one page up to 70 students;
  # beyond, the table runs on and repeats its header.
  defp density(%{students: students}) when length(students) > 60, do: "dense"
  defp density(%{students: students}) when length(students) > 40, do: "compact"
  defp density(_sheet), do: nil

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
