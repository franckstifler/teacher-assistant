defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{BulletinGroup, BulletinTemplate, Sex}
  alias TeacherAssistantWeb.SanctionLabels

  import TeacherAssistantWeb.OfficialHeaderComponents, only: [official_header: 1]

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

  # --- Subject table (spec bulletin v2 §5.3) ---

  # The competence column: APC trimester and séquence cards (never the annual one).
  defp apc?(template, kind), do: show?(template, :apc) and kind in [:trimester, :sequence]

  # One line per séquence for each subject: the APC trimester card.
  defp apc_lines?(template, kind), do: show?(template, :apc) and kind == :trimester

  # The « Cote » column and box: APC, appreciation grading, coded bands
  # (a card published before the codes has no `cote_codes`).
  defp cote?(template),
    do:
      show?(template, :apc) and template.grading != :grade and
        Map.get(template, :cote_codes, []) != []

  # Mark columns, the period average last.
  defp mark_headers(lang, :trimester, template, n) do
    if apc_lines?(template, :trimester),
      do: ["N/20", "M/20"],
      else:
        Enum.map(1..n//1, fn i -> tr(lang, fn -> gettext("Séq %{n}", n: i) end) end) ++
          [tr(lang, fn -> gettext("Moy. trim.") end)]
  end

  defp mark_headers(lang, :annual, _template, _n),
    do:
      Enum.map(1..3, fn i -> tr(lang, fn -> gettext("Trim %{n}", n: i) end) end) ++
        [tr(lang, fn -> gettext("Moy. ann.") end)]

  defp mark_headers(lang, _kind, _template, _n),
    do: [tr(lang, fn -> gettext("Note") end) <> "/20"]

  # The marks before the period average on a one-line row.
  defp pre_marks(row, :trimester, n), do: Enum.map(0..(n - 1)//1, &comp(row, :sequences, &1))
  defp pre_marks(row, :annual, _n), do: Enum.map(0..2, &comp(row, :trimesters, &1))
  defp pre_marks(_row, _kind, _n), do: []

  # Cells between the subject and the period average.
  defp lead_blanks(kind, template, n) do
    pre =
      case kind do
        :trimester -> if apc_lines?(template, kind), do: 1, else: n
        :annual -> 3
        _ -> 0
      end

    pre + if(apc?(template, kind), do: 1, else: 0)
  end

  defp column_count(kind, template, n),
    do: 1 + lead_blanks(kind, template, n) + 3 + trailing_cols(template)

  # Each séquence of the term with its competence and the subject's mark in it.
  defp sequence_lines(row, competences, n) do
    lines =
      Map.get(competences || %{}, row.context_id) ||
        Enum.map(1..n//1, &%{position: &1, number: nil, text: nil})

    Enum.map(lines, &Map.put(&1, :mark, comp(row, :sequences, &1.position - 1)))
  end

  # The séquence card's one competence.
  defp sequence_competence(row, competences) do
    case Map.get(competences || %{}, row.context_id) do
      [%{text: text} | _] -> text
      _ -> nil
    end
  end

  # Spec bulletin v2 §5.4: subjects per « cote », every code shown, highest first.
  defp cote_counts(subjects, codes) do
    counts = Enum.frequencies_by(subjects, &(&1.mention && Map.get(&1.mention, :code)))
    Enum.map(codes, &{&1, Map.get(counts, &1, 0)})
  end

  defp class_profile_rows?(template, class_average, highest, class_profile) do
    (show?(template, :class_average) and class_average != nil) or
      (show?(template, :class_extremes) and highest != nil) or
      (show?(template, :class_profile) and class_profile != nil)
  end

  # Appreciation (francophone) or Grade + Remark (anglophone), when shown.
  defp mention_cols(template) do
    cond do
      not show?(template, :subject_appreciation) -> 0
      template.grading == :grade -> 2
      true -> 1
    end
  end

  defp flag_col(template, element), do: if(show?(template, element), do: 1, else: 0)

  # Every column after "Note×Coef".
  defp trailing_cols(template) do
    if(cote?(template), do: 1, else: 0) + flag_col(template, :min_max) +
      flag_col(template, :subject_rank) + mention_cols(template) +
      flag_col(template, :teacher_visa)
  end

  attr :row, :map, required: true
  attr :template, :map, required: true
  attr :teachers, :map, required: true

  defp subject_cell(assigns) do
    ~H"""
    {@row.label}
    <div :if={show?(@template, :subject_teacher) and @teachers[@row.context_id]} class="teacher">
      {@teachers[@row.context_id]}
    </div>
    """
  end

  attr :row, :map, required: true
  attr :rowspan, :integer, required: true
  attr :template, :map, required: true

  # The cells from the period average to the visa, spanning the subject's lines.
  defp row_tail(assigns) do
    ~H"""
    <td class="num" rowspan={@rowspan}>
      {fmt(@row.average)}<sup :if={@row.makeup_pending}>R</sup>
    </td>
    <td class="num" rowspan={@rowspan}>{fmt(@row.coefficient)}</td>
    <td class="num" rowspan={@rowspan}>{fmt(@row.note_x_coef)}</td>
    <td :if={cote?(@template)} class="num" rowspan={@rowspan}>
      {@row.mention && Map.get(@row.mention, :code)}
    </td>
    <td :if={show?(@template, :min_max)} class="num" rowspan={@rowspan}>
      {if @row.class_min, do: "#{fmt(@row.class_min)} – #{fmt(@row.class_max)}", else: "—"}
    </td>
    <td :if={show?(@template, :subject_rank)} class="num" rowspan={@rowspan}>
      {subject_rank(@row)}
    </td>
    <%= if show?(@template, :subject_appreciation) do %>
      <%= if @template.grading == :grade do %>
        <% g = grade(@template, @row.average) %>
        <td rowspan={@rowspan}>{g && g.letter}</td>
        <td rowspan={@rowspan}>{g && g.remark}</td>
      <% else %>
        <td rowspan={@rowspan}>{@row.mention && @row.mention.label}</td>
      <% end %>
    <% end %>
    <td :if={show?(@template, :teacher_visa)} rowspan={@rowspan}></td>
    """
  end

  # --- Signatures (spec bulletin v2 §7) ---

  # « Le Proviseur » / « The Principal » for the card's language, then a separator.
  defp head_title(lang, header) do
    titles = Map.get(header, :head_title) || %{}

    case Enum.filter(head_title_parts(lang, titles), & &1) do
      [] -> nil
      parts -> Enum.join(parts, " / ") <> " ·"
    end
  end

  defp head_title_parts(:fr, titles), do: [titles[:fr]]
  defp head_title_parts(:en, titles), do: [titles[:en]]
  defp head_title_parts(:bilingual, titles), do: [titles[:fr], titles[:en]]

  # The name frozen with the card, else today's (cards published before v2).
  defp head_name(template, fallback), do: Map.get(template.header, :head_name) || fallback

  # Snapshots published before these keys existed read them defensively.
  defp subject_rank(row), do: Map.get(row, :subject_rank) || "—"

  defp repeater?(enrollment), do: Map.get(enrollment, :repeater)

  # Snapshots published before A7 carry no `left_on`.
  defp left_on(enrollment), do: Map.get(enrollment, :left_on)

  defp dmy(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

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
