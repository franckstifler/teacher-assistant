defmodule TeacherAssistant.Academics.Subjects do
  @moduledoc "The per-school subject catalog (see the 2026-09-17 spec, §1)."
  require Ash.Query

  alias TeacherAssistant.Academics.{Subject, Workspace}

  def list(%Workspace{id: ws_id}) do
    Subject
    |> Ash.Query.filter(workspace_id == ^ws_id)
    |> Ash.Query.sort([:position, :name])
    |> Ash.read!(authorize?: false)
  end

  def create(%Workspace{id: ws_id}, attrs) do
    Subject
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :workspace_id, ws_id))
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, s} -> {:ok, s}
      {:error, error} -> if duplicate?(error), do: {:error, :duplicate_name}, else: {:error, error}
    end
  end

  def update(%Subject{} = s, attrs) do
    s
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, s} -> {:ok, s}
      {:error, error} -> if duplicate?(error), do: {:error, :duplicate_name}, else: {:error, error}
    end
  end

  def deactivate(%Subject{} = s) do
    s |> Ash.Changeset.for_update(:update, %{active?: false}) |> Ash.update(authorize?: false)
  end

  def delete(%Subject{} = s) do
    :ok = Ash.destroy!(s, authorize?: false)
    :ok
  end

  defp duplicate?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: pvars} ->
        constraint = Keyword.get(pvars, :constraint)
        is_binary(constraint) and String.contains?(constraint, "unique_subject_name")

      _ ->
        false
    end)
  end

  defp duplicate?(_), do: false
end
