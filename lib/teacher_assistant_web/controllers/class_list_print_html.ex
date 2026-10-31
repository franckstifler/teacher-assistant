defmodule TeacherAssistantWeb.ClassListPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.OfficialHeaderComponents, only: [official_header: 1]
  import TeacherAssistantWeb.BulletinPrintHTML, only: [tr: 2]

  embed_templates "class_list_print_html/*"

  defp html_lang(:en), do: "en"
  defp html_lang(_), do: "fr"

  defp sex_letter(:f), do: "F"
  defp sex_letter(_), do: "M"

  # « 12/03/2010 à Yaoundé » (« à / in » when bilingual), either half alone when the other is missing.
  defp birth(lang, %{birth_date: date, birth_place: place}) do
    case {format_date(date), present(place)} do
      {nil, nil} -> nil
      {d, nil} -> d
      {nil, p} -> p
      # Only the word is translated: a bilingual sheet prints the data once.
      {d, p} -> "#{d} #{tr(lang, fn -> gettext("à") end)} #{p}"
    end
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
  defp format_date(_), do: nil

  defp present(text) when is_binary(text), do: if(String.trim(text) == "", do: nil, else: text)
  defp present(_), do: nil

  defp totals(rows) do
    students = Enum.map(rows, fn {row, _n} -> row.student end)

    %{
      total: length(students),
      boys: Enum.count(students, &(&1.sex == :m)),
      girls: Enum.count(students, &(&1.sex == :f)),
      repeaters: Enum.count(rows, fn {row, _n} -> row.enrollment.repeater end)
    }
  end

  # « Le Proviseur » / « The Principal » in the class's language.
  defp head_title(lang, header) do
    titles = Map.get(header, :head_title) || %{}

    parts =
      case lang do
        :fr -> [titles[:fr]]
        :en -> [titles[:en]]
        :bilingual -> [titles[:fr], titles[:en]]
      end

    parts |> Enum.filter(& &1) |> Enum.uniq() |> Enum.join(" / ")
  end
end
