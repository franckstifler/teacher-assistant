defmodule TeacherAssistant.Tenancy do
  @moduledoc """
  Shared cross-tenant write guard.

  Every tenant-owned resource is Ash attribute-multitenant on `workspace_id`,
  which makes *reads* tenant-safe (a query scoped to tenant A never returns
  tenant B's rows). It does not, by itself, stop a *write* that combines two
  structs — or a struct and a raw id — from two different workspaces: nothing
  at the DB layer ties a foreign key's value to the tenant of the row that
  holds it (that would need a composite FK, `reference ...,
  match_with: [workspace_id: :workspace_id]`, deferred — see
  `docs/audits/2026-09-23-school-focus/README.md` §10).

  Until that DB-level guard exists, every domain function that receives more
  than one tenant-owned struct (or a raw id naming one) and writes must call
  `same_workspace/1` before writing.
  """

  @doc """
  Returns `:ok` when every struct in `structs` carries the same
  `workspace_id`, else `{:error, :workspace_mismatch}`.

  Each entry may be any struct or map exposing a `:workspace_id` field
  (real Ash-loaded structs always do; a `nil` value — e.g. an in-memory
  struct built without one — is left out of the uniqueness check, since a
  row that legitimately has no persisted workspace to compare is not itself
  proof of a cross-tenant combination).
  """
  def same_workspace(structs) when is_list(structs) do
    structs
    |> Enum.map(&Map.get(&1, :workspace_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> :ok
      [_single] -> :ok
      _ -> {:error, :workspace_mismatch}
    end
  end
end
