defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{BulletinGroup, BulletinTemplate, Sex}
  alias TeacherAssistantWeb.SanctionLabels

  embed_templates "bulletin_print_html/*"

  @backend TeacherAssistantWeb.Gettext

  @doc """
  Runs `fun` (which calls gettext) in the card's language: French or English, or both
  joined « fr / en » on a bilingual card — once when the two are the same.
  """
  def tr(:fr, fun), do: Gettext.with_locale(@backend, "fr", fun)
  def tr(:en, fun), do: Gettext.with_locale(@backend, "en", fun)

  def tr(:bilingual, fun) do
    case {tr(:fr, fun), tr(:en, fun)} do
      {same, same} -> same
      {fr, en} -> fr <> " / " <> en
    end
  end

  # The header's national block: one column per language.
  defp header_langs(:bilingual), do: [:fr, :en]
  defp header_langs(lang), do: [lang]

  # Lines the school typed (spec KLM6) are in one language: one column, even on a bilingual card.
  defp header_columns(lang, header) do
    case Map.get(header, :official_lines) do
      [_ | _] -> Enum.take(header_langs(lang), 1)
      _ -> header_langs(lang)
    end
  end

  defp official_lines(lang, header),
    do: tr_list(lang, fn -> BulletinTemplate.official_lines(header) end)

  # The school block is one column: a bilingual card uses French for its few words.
  defp school_lines(lang, header),
    do:
      tr_list(if(lang == :en, do: :en, else: :fr), fn -> BulletinTemplate.school_lines(header) end)

  defp tr_list(lang, fun) when lang in [:fr, :en],
    do: Gettext.with_locale(@backend, Atom.to_string(lang), fun)

  defp html_lang(:en), do: "en"
  defp html_lang(_), do: "fr"

  defp show?(template, element), do: BulletinTemplate.show?(template, element)

  # Columns between "Coefficient" and "Note×Coef" for each period kind.
  defp period_cols(:trimester), do: 3
  defp period_cols(:annual), do: 4
  defp period_cols(_), do: 1

  # Appreciation (francophone) or Grade + Remark (anglophone), when shown.
  defp mention_cols(template) do
    cond do
      not show?(template, :subject_appreciation) -> 0
      template.grading == :grade -> 2
      true -> 1
    end
  end

  defp min_max_cols(template), do: if(show?(template, :min_max), do: 1, else: 0)

  defp subject_rank_cols(template), do: if(show?(template, :subject_rank), do: 1, else: 0)

  # Every column after "Note×Coef".
  defp trailing_cols(template),
    do: mention_cols(template) + min_max_cols(template) + subject_rank_cols(template)

  # Snapshots published before these keys existed read them defensively.
  defp subject_rank(row), do: Map.get(row, :subject_rank) || "—"

  defp repeater?(enrollment), do: Map.get(enrollment, :repeater)

  defp body_cols(kind, template), do: 2 + period_cols(kind) + 1 + trailing_cols(template)

  defp grade(template, mark), do: BulletinTemplate.grade(template.grade_scale, mark)

  defp fmt(nil), do: "—"

  defp fmt(%Decimal{} = d) do
    str = d |> Decimal.round(2) |> Decimal.to_string()

    if Gettext.get_locale(TeacherAssistantWeb.Gettext) == "fr",
      do: String.replace(str, ".", ","),
      else: str
  end

  defp comp(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp sex_label(s), do: Sex.label(s)

  defp group_label(g), do: BulletinGroup.label(g)

  defp sanctions_line(sanctions), do: SanctionLabels.sanctions_line(sanctions)
end
