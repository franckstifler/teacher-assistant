defmodule TeacherAssistant.SchemaTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics, as: A

  @tenant_owned [
    A.AcademicYear,
    A.Term,
    A.Sequence,
    A.Subject,
    A.Period,
    A.ClassGroup,
    A.Student,
    A.Enrollment,
    A.TeachingContext,
    A.CombinedCourse,
    A.ProgressionPlan,
    A.ProgressionModule,
    A.ProgressionEntry,
    A.LessonPlan,
    A.LessonStep,
    A.TeachingLogEntry,
    A.Assessment,
    A.Mark,
    A.AttendanceEntry,
    A.TimetableSlot,
    A.SanctionEntry,
    A.ConductMark,
    A.FeeTranche,
    A.Payment,
    A.FeeAdjustment,
    TeacherAssistant.Accounts.SchoolMembership,
    TeacherAssistant.Accounts.SchoolInvitation
  ]

  test "every tenant-owned resource belongs to a workspace, not-null" do
    for resource <- @tenant_owned do
      rel = Ash.Resource.Info.relationship(resource, :workspace)
      assert rel, "#{inspect(resource)} has no :workspace relationship"
      assert rel.type == :belongs_to
      refute rel.allow_nil?, "#{inspect(resource)}.workspace allows nil"
      attr = Ash.Resource.Info.attribute(resource, :workspace_id)
      assert attr && attr.type == Ash.Type.UUID
    end
  end

  test "every foreign key column is indexed" do
    missing =
      for resource <- @tenant_owned,
          rel <- Ash.Resource.Info.relationships(resource),
          rel.type == :belongs_to,
          table = AshPostgres.DataLayer.Info.table(resource),
          not indexed?(table, rel.source_attribute) do
        {table, rel.source_attribute}
      end

    assert missing == []
  end

  # A column counts as indexed if it appears anywhere in an index's column
  # list, not only in the leading position. Attribute multitenancy prepends
  # the tenant column (`workspace_id`) to every index/identity AshPostgres
  # generates for a multitenant resource, so e.g. `terms`' FK index on
  # `academic_year_id` is now `(workspace_id, academic_year_id)` — still a
  # real index covering that column, just no longer leading.
  defp indexed?(table, column) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        TeacherAssistant.Repo,
        "SELECT indexdef FROM pg_indexes WHERE tablename = $1",
        [table]
      )

    Enum.any?(rows, fn [def] -> to_string(column) in index_columns(def) end)
  end

  defp index_columns(indexdef) do
    case Regex.run(~r/\(([^)]*)\)/, indexdef) do
      [_, cols] -> cols |> String.split(",") |> Enum.map(&String.trim/1)
      _ -> []
    end
  end

  test "every :workspace reference cascades on delete" do
    missing =
      for resource <- @tenant_owned,
          reference <- AshPostgres.DataLayer.Info.references(resource),
          reference.relationship == :workspace,
          reference.on_delete != :delete do
        {resource, reference.on_delete}
      end

    assert missing == []
  end

  # F2 (gate fix wave): the tenancy migrations dropped these plain,
  # FK-leading indexes in favor of `(workspace_id, <col>)` composites. Those
  # composites can't serve a tenant-less scan (`SchoolMembership
  # :active_for_user`, global) or a delete-time FK check (Postgres needs the
  # referenced column leading, not preceded by an unrelated workspace_id) —
  # `gate_indexes` re-adds the plain ones alongside the composites.
  @gate_indexes [
    {TeacherAssistant.Accounts.SchoolMembership, :user_id},
    {A.AttendanceEntry, :enrollment_id},
    {A.AttendanceEntry, :period_id},
    {A.Mark, :student_id},
    {A.Mark, :assessment_id},
    {A.Payment, :enrollment_id}
  ]

  test "the gate_indexes migration's FK-leading and global-read indexes exist" do
    missing =
      for {resource, column} <- @gate_indexes,
          table = AshPostgres.DataLayer.Info.table(resource),
          not leading_indexed?(table, column) do
        {table, column}
      end

    assert missing == []
  end

  # Stricter than `indexed?/2`: the column must be the FIRST column of some
  # index — a `(workspace_id, enrollment_id)` composite (leading with the
  # tenant column) does not count. This is the actual property `gate_indexes`
  # adds: a plain, single-column index that a tenant-less scan or a
  # delete-time FK check on the referenced table can use.
  defp leading_indexed?(table, column) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        TeacherAssistant.Repo,
        "SELECT indexdef FROM pg_indexes WHERE tablename = $1",
        [table]
      )

    Enum.any?(rows, fn [def] ->
      case index_columns(def) do
        [first | _] -> first == to_string(column)
        [] -> false
      end
    end)
  end
end
