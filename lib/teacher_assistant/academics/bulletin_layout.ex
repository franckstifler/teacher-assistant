defmodule TeacherAssistant.Academics.BulletinLayout do
  @moduledoc """
  Spec bulletin v2 §5.6: a report card always fits one A4 page. The print picks a
  density tier (font size and cell padding) from how many lines the card holds;
  past the densest tier the publish checklist warns instead of dropping anything.
  Capacities were measured in the browser (see the spec).
  """

  # Effective lines (subject lines + identity rows) each tier holds.
  @tiers [normal: 26, compact: 38, dense: 46]

  @doc """
  Lines the subject table takes: one per subject row, or one per séquence of the term
  on an APC trimester card, plus each group's header row and, with subtotals, its total.
  """
  def subject_lines(template, period_kind, groups, sequences_per_term, group_subtotals?) do
    per_row = if apc_lines?(template, period_kind), do: sequences_per_term, else: 1
    rows = groups |> Enum.map(&length(&1.rows)) |> Enum.sum()
    extra = if group_subtotals?, do: 2 * length(groups), else: length(groups)
    rows * per_row + extra
  end

  @doc "Rows of the identity block: four, plus one for the parents."
  def identity_rows(template), do: if(:guardians in template.elements, do: 5, else: 4)

  @doc "`:normal | :compact | :dense`, or `:overflow` past the densest tier."
  def density(subject_lines, identity_rows) do
    lines = subject_lines + identity_rows
    Enum.find_value(@tiers, :overflow, fn {tier, max} -> if lines <= max, do: tier end)
  end

  defp apc_lines?(template, :trimester), do: :apc in template.elements
  defp apc_lines?(_template, _kind), do: false
end
