defmodule TeacherAssistant.Academics.CoefficientRules do
  @moduledoc """
  Pure coefficient-grid rules. `cells` is a map keyed `{subject_id, subsystem, level, serie}`
  (values: anything non-nil). An assignment resolves to its série's cell, else to its
  level's blank-série cell, else to nothing (not taught there).
  """

  def resolve(cells, %{subject_id: s, subsystem: sub, level: l, serie: serie}) do
    cond do
      serie != nil and Map.has_key?(cells, {s, sub, l, serie}) -> {s, sub, l, serie}
      Map.has_key?(cells, {s, sub, l, nil}) -> {s, sub, l, nil}
      true -> nil
    end
  end
end
