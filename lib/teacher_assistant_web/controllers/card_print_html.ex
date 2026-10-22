defmodule TeacherAssistantWeb.CardPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_photo_url: 1]
  import TeacherAssistantWeb.BulletinPrintHTML, only: [tr: 2]

  embed_templates "card_print_html/*"

  def html_lang(:en), do: "en"
  def html_lang(_), do: "fr"

  def sex_label(:f), do: "F"
  def sex_label(:m), do: "M"
  def sex_label(_), do: "—"

  alias TeacherAssistant.Academics.BulletinTemplate

  @doc """
  Spec bulletin v2 §7: the card's short national lines in one language — the first two,
  then the delegations on one line.
  """
  def card_lines(header, lang) do
    case BulletinTemplate.official_lines(header, lang) do
      [country, motto | rest] -> [country, motto, Enum.join(rest, " · ")]
      lines -> lines
    end
  end

  @doc "Address, phone and school code on one line."
  def contact_line(header) do
    [
      header.address,
      present(header.phone) && "Tél. #{header.phone}",
      present(Map.get(header, :school_code)) && "Code #{header.school_code}"
    ]
    |> Enum.filter(&present/1)
    |> Enum.join(" · ")
  end

  @doc "« Le Proviseur · The Principal », or « The Principal » alone (anglophone schools)."
  def head_title(header) do
    titles = Map.get(header, :head_title) || %{}
    [titles[:fr], titles[:en]] |> Enum.filter(& &1) |> Enum.join(" · ")
  end

  defp present(text), do: is_binary(text) and String.trim(text) != ""

  def date(nil), do: nil
  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
