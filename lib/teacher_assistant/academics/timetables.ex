defmodule TeacherAssistant.Academics.Timetables do
  @moduledoc "Bell schedule periods for a workspace (P2.7)."

  require Ash.Query

  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Academics.Workspace

  def list_periods(%Workspace{id: ws_id}) do
    Period
    |> Ash.Query.filter(workspace_id == ^ws_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def build_default_periods(%Workspace{} = ws) do
    case list_periods(ws) do
      [] ->
        Enum.each(Reference.default_periods_preset(), fn preset ->
          Period
          |> Ash.Changeset.for_create(:create, Map.put(preset, :workspace_id, ws.id))
          |> Ash.create!(authorize?: false)
        end)

        :ok

      _ ->
        :ok
    end
  end
end
