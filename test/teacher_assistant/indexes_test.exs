defmodule TeacherAssistant.IndexesTest do
  @moduledoc "The indexes the register, the journal and the lists read by (A8)."
  use TeacherAssistant.DataCase, async: true

  @expected [
    {"typed_absences", "workspace_id, sequence_id"},
    {"typed_absences", "workspace_id, term_id"},
    {"mark_events", "workspace_id, assessment_id"},
    {"mark_events", "workspace_id, student_id"},
    {"attendance_entries", "workspace_id, inserted_at"},
    {"payments", "workspace_id, inserted_at"},
    {"sanction_entries", "workspace_id, inserted_at"}
  ]

  test "the A8 indexes exist" do
    %{rows: rows} =
      TeacherAssistant.Repo.query!(
        "SELECT tablename, indexdef FROM pg_indexes WHERE schemaname = 'public'"
      )

    for {table, cols} <- @expected do
      assert Enum.any?(rows, fn [t, defn] -> t == table and defn =~ "(#{cols})" end),
             "no index on #{table} (#{cols})"
    end
  end
end
