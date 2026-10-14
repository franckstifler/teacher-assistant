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

  def date(nil), do: nil
  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
end
