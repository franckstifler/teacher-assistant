defmodule TeacherAssistantWeb.CardPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_photo_url: 1]
  import TeacherAssistantWeb.BulletinPrintHTML, only: [tr: 2]

  alias TeacherAssistant.Academics.BulletinTemplate

  embed_templates "card_print_html/*"

  def html_lang(:en), do: "en"
  def html_lang(_), do: "fr"

  def sex_label(:f), do: "F"
  def sex_label(:m), do: "M"
  def sex_label(_), do: "—"

  @doc """
  A card label in the class's language: one language, or « Classe · Class » for a
  bilingual school (the same word once).
  """
  def card_label(lang, fun), do: lang |> card_lines(fun) |> Enum.join(" · ")

  @doc "The same text as lines: one per language (`:bilingual`: French, then English)."
  def card_lines(:bilingual, fun), do: Enum.uniq([tr(:fr, fun), tr(:en, fun)])
  def card_lines(lang, fun), do: [tr(lang, fun)]

  @doc """
  « République du Cameroun · Republic of Cameroon »: the first national line of each
  language's header, on one line (the card is a national document, so both).
  """
  def republic_line(header) do
    [:fr, :en]
    |> Enum.map(&List.first(BulletinTemplate.official_lines(header, &1)))
    |> Enum.filter(&present/1)
    |> Enum.uniq()
    |> Enum.join(" · ")
  end

  @doc "School code, phone and address on one line (the code first: it is cut last)."
  def contact_line(header) do
    [
      present(Map.get(header, :school_code)) && "Code #{header.school_code}",
      present(header.phone) && "Tél. #{header.phone}",
      header.address
    ]
    |> Enum.filter(&present/1)
    |> Enum.join(" · ")
  end

  @doc "« Le Proviseur · The Principal », or « The Principal » alone (anglophone schools)."
  def head_title(header) do
    titles = Map.get(header, :head_title) || %{}
    [titles[:fr], titles[:en]] |> Enum.filter(& &1) |> Enum.join(" · ")
  end

  @doc """
  The caption printed at the top of each sheet: class, sheet i / n, how many cards, and
  the print setting that keeps the cards at ID-1 size.
  """
  def sheet_caption(class_label, index, total, cards) do
    gettext("%{class} · planche %{i} / %{n} · %{cards} · A4, échelle 100 %",
      class: class_label,
      i: index,
      n: total,
      cards: ngettext("%{count} carte", "%{count} cartes", cards)
    )
  end

  # The 2 × 5 grid's place on the A4 sheet (mm), and its crop marks: a 4 mm tick 2 mm
  # off the grid at each column edge (above and below) and each row edge (left, right).
  @grid_left 19.3
  @grid_top 13.3
  @card_w 85.6
  @card_h 54.0
  @tick 4.0
  @gap 2.0

  @doc "The sheet's crop marks, as `{class, style}`."
  def crop_marks do
    xs = for i <- 0..2, do: @grid_left + i * @card_w
    ys = for i <- 0..5, do: @grid_top + i * @card_h
    right = @grid_left + 2 * @card_w
    bottom = @grid_top + 5 * @card_h

    vertical =
      Enum.flat_map(xs, fn x ->
        [
          {:v, x, @grid_top - @gap - @tick},
          {:v, x, bottom + @gap}
        ]
      end)

    horizontal =
      Enum.flat_map(ys, fn y ->
        [
          {:h, @grid_left - @gap - @tick, y},
          {:h, right + @gap, y}
        ]
      end)

    Enum.map(vertical ++ horizontal, fn
      {:v, x, y} -> {"mark mark-v", "left: #{mm(x)}; top: #{mm(y)}; height: #{mm(@tick)}"}
      {:h, x, y} -> {"mark mark-h", "left: #{mm(x)}; top: #{mm(y)}; width: #{mm(@tick)}"}
    end)
  end

  defp mm(value), do: "#{:erlang.float_to_binary(value * 1.0, decimals: 2)}mm"

  defp present(text), do: is_binary(text) and String.trim(text) != ""

  def date(nil), do: nil
  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
