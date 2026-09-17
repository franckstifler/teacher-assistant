defmodule TeacherAssistant.Academics.Seeding do
  @moduledoc "One-time starter classes for a school's first academic year (spec §3)."
  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{AcademicYear, ClassGroup, SchoolTemplates, Workspace}
  alias TeacherAssistant.Accounts.Schools

  def seed_starter_classes(%Workspace{} = ws, %AcademicYear{} = year) do
    if has_any_class?(ws) do
      {:ok, 0}
    else
      {:ok, profile} = Schools.fetch_school_profile(ws)
      rows = SchoolTemplates.classes_for(profile.school_type, profile.subsystem)

      Enum.each(rows, fn %{label: label, level: level, serie: serie} ->
        {:ok, _} = Academics.create_class_group(ws, year, %{label: label, level: level, serie: serie})
      end)

      {:ok, length(rows)}
    end
  end

  defp has_any_class?(%Workspace{id: ws_id}) do
    ClassGroup
    |> Ash.Query.filter(workspace_id == ^ws_id)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [] -> false
      _ -> true
    end
  end
end
