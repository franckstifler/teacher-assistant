defmodule TeacherAssistant.Academics.BulletinTemplate do
  @moduledoc """
  The printed report card's template (spec I5), pure: language, grading column,
  elements shown, grade scale and header, resolved from the school profile for one
  class. Publishing stores the resolved map in the snapshot.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.BulletinElement

  @doc "The common in-school scale, lowest band first. Remarks are English (anglophone cards)."
  def default_grade_scale do
    [
      {"0", "F", "Fail"},
      {"8", "E", "Weak"},
      {"10", "D", "Pass"},
      {"12", "C", "Good"},
      {"14", "B", "Very good"},
      {"16", "A", "Excellent"}
    ]
    |> Enum.map(fn {from, letter, remark} ->
      %{from: Decimal.new(from), letter: letter, remark: remark}
    end)
  end

  @doc "The elements shown: nil = defaults; a list (even empty) as chosen."
  def elements(nil), do: BulletinElement.defaults()
  def elements(list) when is_list(list), do: list

  @doc "The grade scale in force, as plain maps."
  def grade_scale(bands) when bands in [nil, []], do: default_grade_scale()

  def grade_scale(bands),
    do: Enum.map(bands, &%{from: &1.from, letter: &1.letter, remark: &1.remark})
end
