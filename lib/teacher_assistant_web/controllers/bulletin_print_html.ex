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

  # Spec bulletin v2 §5.1: French on the left, English on the right, on every card.
  defp official_lines(header, lang), do: BulletinTemplate.official_lines(header, lang)

  # The school's own lines under each column; the English one names the school in English.
  defp school_lines(header, :fr),
    do: tr_list(:fr, fn -> BulletinTemplate.school_lines(header) end)

  defp school_lines(header, :en) do
    name = if present?(Map.get(header, :name_en)), do: header.name_en, else: header.name
    tr_list(:en, fn -> BulletinTemplate.school_lines(%{header | name: name}) end)
  end

  defp tr_list(lang, fun) when lang in [:fr, :en],
    do: Gettext.with_locale(@backend, Atom.to_string(lang), fun)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  defp guardians_line(guardians),
    do:
      Enum.map_join(guardians, " · ", fn g ->
        Enum.join(Enum.filter([g.name, g.phone], & &1), " — ")
      end)

  @doc """
  Spec bulletin v2 §5.2: the card's title, naming its period (`n`: the trimester's
  position or the séquence's number).
  """
  def title(lang, :trimester, n), do: tr(lang, fn -> trimester_title(n) end)
  def title(lang, :annual, _n), do: tr(lang, fn -> gettext("Bulletin annuel") end)

  def title(lang, :sequence, n),
    do: tr(lang, fn -> gettext("Bulletin de la séquence %{n}", n: n) end)

  defp trimester_title(1), do: gettext("Bulletin scolaire du premier trimestre")
  defp trimester_title(2), do: gettext("Bulletin scolaire du deuxième trimestre")
  defp trimester_title(3), do: gettext("Bulletin scolaire du troisième trimestre")
  defp trimester_title(n), do: gettext("Bulletin scolaire du trimestre %{n}", n: n)

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
