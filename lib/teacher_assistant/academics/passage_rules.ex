defmodule TeacherAssistant.Academics.PassageRules do
  @moduledoc """
  A school's passage rules (spec I4), as a pure struct, and the decision they propose
  for a student at the end of the year. Built from the school profile by
  `TeacherAssistant.Assessment.passage_rules/1`. A nil threshold switches its rule off.
  The engine only proposes; the annual class council confirms or overrides.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  defstruct passage_min: Decimal.new(10),
            rachat_min: Decimal.new("9.5"),
            exclusion_below: Decimal.new(7),
            one_repeat_per_cycle?: true,
            exclusion_on_conduct?: true,
            exclusion_absence_hours: 60

  @conduct_min Decimal.new(10)

  @doc "The fixed conduct minimum of the conduct rule."
  def conduct_minimum, do: @conduct_min

  @doc """
  `{decision, reason}` for a student — `average` (annual), `repeater?` (this year),
  `conduct` (annual note de conduite, nil = none) and `unjustified_hours` — or nil without
  an average. Exclusion reasons come first; Admis and Admis par rachat have no reason.
  """
  def propose(%{average: nil}, _rules), do: nil

  def propose(%{average: %Decimal{} = average} = student, %__MODULE__{} = rules) do
    exclusion_reason(average, student, rules) || by_average(average, student, rules)
  end

  defp exclusion_reason(average, student, rules) do
    cond do
      below?(average, rules.exclusion_below) ->
        {:exclu, gettext("Moyenne < %{min}", min: show(rules.exclusion_below))}

      rules.exclusion_on_conduct? and below?(student[:conduct], @conduct_min) ->
        {:exclu, gettext("Conduite < 10")}

      absent_too_long?(student[:unjustified_hours], rules.exclusion_absence_hours) ->
        {:exclu,
         gettext("%{hours} h d'absences non justifiées", hours: rules.exclusion_absence_hours)}

      true ->
        nil
    end
  end

  defp by_average(average, student, rules) do
    cond do
      not below?(average, rules.passage_min) ->
        {:admis, nil}

      rules.rachat_min && not below?(average, rules.rachat_min) ->
        {:admis_rachat, nil}

      rules.one_repeat_per_cycle? and student[:repeater?] == true ->
        {:exclu, gettext("Déjà redoublant")}

      true ->
        {:redouble, nil}
    end
  end

  defp below?(nil, _threshold), do: false
  defp below?(_value, nil), do: false
  defp below?(value, threshold), do: Decimal.compare(value, threshold) == :lt

  defp absent_too_long?(_hours, nil), do: false
  defp absent_too_long?(nil, _limit), do: false

  defp absent_too_long?(hours, limit),
    do: Decimal.compare(Decimal.new(to_string(hours)), Decimal.new(limit)) != :lt

  defp show(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
end
