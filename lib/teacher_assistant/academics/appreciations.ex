defmodule TeacherAssistant.Academics.Appreciations do
  @moduledoc """
  A school's appreciation scale and distinctions (spec I1), pure. The scale is a list
  of bands, each `%{from, label}`: a band covers `from` ≤ average < the next band's
  `from`, and the last band includes 20. With no saved bands the default scale applies,
  its labels translated; saved labels are shown as typed.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.GradingRules

  @pass Decimal.new(10)
  @conduct_min Decimal.new(12)

  @honours [
    felicitations: :felicitations_min,
    encouragements: :encouragements_min,
    tableau_honneur: :tableau_honneur_min
  ]

  def pass_mark, do: @pass
  def conduct_minimum, do: @conduct_min

  @doc "The default scale (labels in the current locale)."
  def default_bands do
    [
      {"0", gettext("Très insuffisant")},
      {"5", gettext("Insuffisant")},
      {"8", gettext("Médiocre")},
      {"10", gettext("Passable")},
      {"12", gettext("Assez bien")},
      {"14", gettext("Bien")},
      {"16", gettext("Très bien")},
      {"18", gettext("Excellent")}
    ]
    |> Enum.map(fn {from, label} -> %{from: Decimal.new(from), label: label} end)
  end

  @doc "The scale in force under `rules`, lowest band first."
  def bands(%GradingRules{appreciation_bands: bands}) when bands in [nil, []],
    do: default_bands()

  def bands(%GradingRules{appreciation_bands: bands}),
    do: Enum.map(bands, &%{from: &1.from, label: &1.label})

  @doc "`%{label, position, passed?}` for `average`, or nil when there is no average."
  def appreciation(nil, _rules), do: nil

  def appreciation(%Decimal{} = average, %GradingRules{} = rules) do
    [first | _] = indexed = rules |> bands() |> Enum.with_index()

    {band, position} =
      Enum.reduce(indexed, first, fn {band, _} = entry, acc ->
        if gte(average, band.from), do: entry, else: acc
      end)

    %{label: band.label, position: position, passed?: gte(average, @pass)}
  end

  @doc """
  The distinction earned with `moyenne`: the highest honour roll whose threshold is
  met and whose gates pass, else a work warning (blâme before avertissement), else nil.
  `subject_averages` are the student's subject averages (nil = ungraded, never blocks);
  `conduct` is the period's note de conduite (nil = none, never blocks).
  """
  def distinction(nil, _subject_averages, _conduct, _rules), do: nil

  def distinction(%Decimal{} = moyenne, subject_averages, conduct, %GradingRules{} = rules) do
    honour(moyenne, subject_averages, conduct, rules) || warning(moyenne, rules)
  end

  defp honour(moyenne, subject_averages, conduct, rules) do
    if all_passed_ok?(subject_averages, rules) and conduct_ok?(conduct, rules) do
      Enum.find_value(@honours, fn {kind, field} ->
        threshold = Map.fetch!(rules, field)
        if threshold && gte(moyenne, threshold), do: kind
      end)
    end
  end

  defp warning(moyenne, rules) do
    cond do
      below?(moyenne, rules.blame_travail_below) -> :blame_travail
      below?(moyenne, rules.avertissement_travail_below) -> :avertissement_travail
      true -> nil
    end
  end

  defp all_passed_ok?(_averages, %GradingRules{distinctions_require_all_passed?: false}),
    do: true

  defp all_passed_ok?(averages, _rules),
    do: Enum.all?(averages, &(is_nil(&1) or gte(&1, @pass)))

  defp conduct_ok?(_conduct, %GradingRules{distinctions_require_conduct?: false}), do: true
  defp conduct_ok?(nil, _rules), do: true
  defp conduct_ok?(conduct, _rules), do: gte(conduct, @conduct_min)

  defp below?(_value, nil), do: false
  defp below?(value, threshold), do: Decimal.compare(value, threshold) == :lt

  defp gte(a, b), do: Decimal.compare(a, b) != :lt
end
