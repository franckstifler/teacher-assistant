defmodule TeacherAssistant.Academics.Seeding do
  @moduledoc "One-time starter classes for a school's first academic year (spec §3)."

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Scope
  alias TeacherAssistant.Academics.{AcademicYear, ClassGroup, SchoolTemplates}
  alias TeacherAssistant.Accounts

  def seed_starter_classes(%Scope{} = scope, %AcademicYear{} = year) do
    if has_any_class?(scope) do
      {:ok, 0}
    else
      with {:ok, profile} <- Accounts.fetch_school_profile(scope) do
        rows = SchoolTemplates.classes_for(profile.school_type, profile.subsystem)

        Enum.reduce_while(rows, {:ok, 0}, fn %{label: label, level: level, serie: serie},
                                             {:ok, n} ->
          case Enrollment.create_class_group(scope, year, %{
                 label: label,
                 level: level,
                 serie: serie
               }) do
            {:ok, _} -> {:cont, {:ok, n + 1}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
      end
    end
  end

  defp has_any_class?(%Scope{} = scope) do
    ClassGroup
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.exists?()
  end
end
