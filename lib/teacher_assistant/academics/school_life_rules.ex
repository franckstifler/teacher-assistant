defmodule TeacherAssistant.Academics.SchoolLifeRules do
  @moduledoc """
  A school's attendance and discipline settings (spec KLM2) as a pure struct,
  built from the school profile by `TeacherAssistant.Attendance.school_life_rules/1`.
  """

  alias TeacherAssistant.Academics.SanctionType

  @default_points %{
    consigne: Decimal.new(1),
    avertissement: Decimal.new(2),
    blame: Decimal.new(4),
    exclusion_temporaire: Decimal.new(6),
    exclusion_definitive: Decimal.new(0),
    conseil_discipline: Decimal.new(0)
  }

  defstruct late_as_absence_minutes: nil,
            justification_deadline_days: nil,
            absence_alert_hours: 10,
            points_per_absence_hour: Decimal.new("0.5"),
            points_per_late: Decimal.new("0.25"),
            sanction_points: @default_points,
            sanction_types_in_use: SanctionType.values()

  def from_profile(profile) do
    %__MODULE__{
      late_as_absence_minutes: profile.late_as_absence_minutes,
      justification_deadline_days: profile.justification_deadline_days,
      absence_alert_hours: profile.absence_alert_hours,
      points_per_absence_hour: profile.conduct_points_per_absence_hour,
      points_per_late: profile.conduct_points_per_late,
      sanction_points: points(profile.sanction_points),
      sanction_types_in_use: profile.sanction_types_in_use || SanctionType.values()
    }
  end

  defp points(nil), do: @default_points
  # A type added after the school saved its points (e.g. :conseil_discipline) takes the default.
  defp points(%{} = embedded),
    do:
      Map.new(
        SanctionType.values(),
        &{&1, Map.get(embedded, &1) || Map.fetch!(@default_points, &1)}
      )

  @doc "The settings page's worked example: 6 unjustified hours, 2 lates, 1 avertissement."
  def example_mark(%__MODULE__{} = rules) do
    Decimal.new(20)
    |> Decimal.sub(Decimal.mult(6, rules.points_per_absence_hour))
    |> Decimal.sub(Decimal.mult(2, rules.points_per_late))
    |> Decimal.sub(rules.sanction_points[:avertissement])
    |> Decimal.max(0)
    |> Decimal.min(20)
  end
end
