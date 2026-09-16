defmodule TeacherAssistant.Accounts.SchoolTypes do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @order [
    :lycee,
    :ces_ceg,
    :lycee_technique,
    :cetic,
    :gss,
    :ghs,
    :gbss,
    :gbhs,
    :gtc,
    :gths,
    :sar_sm
  ]
  def all, do: @order
  def label(:lycee), do: gettext("Lycée")
  def label(:ces_ceg), do: gettext("CES / CEG")
  def label(:lycee_technique), do: gettext("Lycée technique")
  def label(:cetic), do: gettext("CETIC")
  def label(:gss), do: gettext("Government Secondary School (GSS)")
  def label(:ghs), do: gettext("Government High School (GHS)")
  def label(:gbss), do: gettext("Govt Bilingual Secondary School (GBSS)")
  def label(:gbhs), do: gettext("Govt Bilingual High School (GBHS)")
  def label(:gtc), do: gettext("Government Technical College (GTC)")
  def label(:gths), do: gettext("Government Technical High School (GTHS)")
  def label(:sar_sm), do: gettext("SAR/SM")
end
