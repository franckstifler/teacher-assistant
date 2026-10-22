defmodule TeacherAssistant.Accounts.HeadTitle do
  @moduledoc """
  Spec bulletin v2 §7: the head's printed title by school type (docs/domain/05 §1).
  Lycées have a Proviseur, collèges a Directeur; anglophone schools have only a
  Principal, so they print no French title.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @proviseur [:lycee, :lycee_technique]
  @directeur [:ces_ceg, :cetic, :sar_sm]

  def title(_type, :en),
    do: Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn -> gettext("The Principal") end)

  def title(type, :fr) when type in @proviseur, do: gettext("Le Proviseur")
  def title(type, :fr) when type in @directeur, do: gettext("Le Directeur")
  def title(_type, :fr), do: nil
end
