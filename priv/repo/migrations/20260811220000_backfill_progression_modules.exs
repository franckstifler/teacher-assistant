defmodule TeacherAssistant.Repo.Migrations.BackfillProgressionModules do
  use Ecto.Migration
  import Ecto.Query
  alias TeacherAssistant.Repo
  alias TeacherAssistant.Academics.ModuleGrouping

  # French default-bucket title; EN column comes from gettext at render time, but the
  # stored title is a plain string, so we store the FR label (teacher-editable later).
  @default_title "Général"

  def up do
    plan_ids =
      from(p in "progression_plans", select: p.id) |> Repo.all()

    Enum.each(plan_ids, &backfill_plan/1)
  end

  def down do
    # Non-reversible data migration; the column drop in the paired schema migration
    # is what `down` there restores. Nothing to undo here.
    :ok
  end

  defp backfill_plan(plan_id) do
    entries =
      from(e in "progression_entries",
        where: e.progression_plan_id == ^plan_id,
        select: %{id: e.id, module: e.module, position: e.position}
      )
      |> Repo.all()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries
    |> ModuleGrouping.group()
    |> Enum.with_index(1)
    |> Enum.each(fn {%{key: key, entry_ids: entry_ids}, mod_position} ->
      # NOTE: these schemaless queries have no Ecto type info, so Postgrex
      # round-trips `:uuid` columns as raw 16-byte binaries (confirmed empirically:
      # `entries` selected above already came back with raw-binary `id`/`progression_plan_id`
      # values, and passing a *string* UUID like `Ecto.UUID.generate()` to insert_all/update_all
      # here raises `DBConnection.EncodeError`). `Ecto.UUID.bingenerate/0` produces a
      # freshly-generated UUID already in that raw-binary form.
      module_id = Ecto.UUID.bingenerate()
      default? = key == :default
      title = if default?, do: @default_title, else: key

      Repo.insert_all("progression_modules", [
        %{
          id: module_id,
          title: title,
          position: mod_position,
          default?: default?,
          progression_plan_id: plan_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      entry_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {entry_id, entry_position} ->
        from(e in "progression_entries", where: e.id == ^entry_id)
        |> Repo.update_all(
          set: [progression_module_id: module_id, position: entry_position]
        )
      end)
    end)
  end
end
