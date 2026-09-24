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
end
