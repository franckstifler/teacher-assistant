defmodule TeacherAssistant.Academics.AbsenceTotals do
  @moduledoc """
  Spec 2026-11-23 « Bilan des absences »: the threshold rules and the « over the
  threshold » filter over `TeacherAssistant.Attendance.absence_totals/3` groups.
  Pure: no reads.

  The threshold is in unjustified hours, typed on the page; its default is 20 h per
  séquence of the period. It is the page's own figure: the school's « seuil d'alerte »
  (`absence_alert_hours`) keeps its role on « Absences ».
  """

  @hours_per_sequence 20

  @doc "20 h per séquence of the period (20 h when the period has none yet)."
  def default_threshold(sequence_count) when is_integer(sequence_count),
    do: Decimal.new(@hours_per_sequence * max(sequence_count, 1))

  @doc "A typed threshold (« 12,5 » or « 12.5 »); anything not a positive number gives `default`."
  def parse_threshold(param, default) when is_binary(param) do
    case param |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {hours, ""} -> if Decimal.gt?(hours, 0), do: hours, else: default
      _ -> default
    end
  end

  def parse_threshold(_param, default), do: default

  @doc "Whether a row's unjustified hours reach the threshold."
  def flagged?(%{unjustified_hours: hours}, threshold),
    do: Decimal.compare(hours, threshold) != :lt

  @doc """
  The groups with their flagged rows only, most unjustified hours first (then by name);
  a group left with none is dropped. Group order is kept.
  """
  def over_threshold(groups, threshold) do
    for group <- groups,
        rows = Enum.filter(group.rows, &flagged?(&1, threshold)),
        rows != [] do
      # Stable sorts: by name, then by hours descending.
      rows =
        rows
        |> Enum.sort_by(& &1.student.full_name)
        |> Enum.sort_by(& &1.unjustified_hours, {:desc, Decimal})

      %{group | rows: rows}
    end
  end
end
