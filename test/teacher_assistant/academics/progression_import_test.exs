defmodule TeacherAssistant.Academics.ProgressionImportTest do
  use TeacherAssistant.DataCase

  require Ash.Query

  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionImport

  setup %{tenant: tenant, user: admin} do
    teacher = generate(user(tenant: tenant, role: :teacher))
    generate(user_school(tenant: tenant, user_id: teacher.id, role: teacher.role))
    academic_year = generate(academic_year(tenant: tenant, actor: admin))
    level_option = generate(level_option(tenant: tenant, actor: admin))
    subject = generate(subject(tenant: tenant, actor: admin, name: "Mathematics"))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 4},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

    plan =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionPlan,
        %{
          academic_year_id: academic_year.id,
          classroom_id: classroom.id,
          level_option_subject_id: level_option_subject.id,
          teacher_id: teacher.id,
          weekly_hours: Decimal.new("4"),
          annual_hours: Decimal.new("96"),
          status: :active
        },
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    scope = TeacherAssistant.Accounts.Workspaces.scope_for!(teacher, tenant.id)

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :pdftotext_path)
    end)

    %{scope: scope, plan: plan, tenant: tenant, teacher: teacher}
  end

  test "extracts and previews rows from a Word or Excel exported progression PDF", %{
    scope: scope,
    plan: plan
  } do
    configure_fake_pdftotext("""
    Week   Start        End          Lesson                         Content                         Hours
    1      2026-09-01   2026-09-05   Linear equations               Solving first-degree equations  4
    2      2026-09-08   2026-09-12   Factorisation                  Common factor and identities    3.5
    """)

    assert {:ok, preview} = ProgressionImport.preview_rows(scope, plan.id, pdf_path())

    assert [
             %{
               week_number: 1,
               start_date: ~D[2026-09-01],
               end_date: ~D[2026-09-05],
               title: "Linear equations",
               planned_content: "Solving first-degree equations",
               planned_hours: %Decimal{} = hours,
               duplicate?: false,
               errors: []
             },
             %{week_number: 2, title: "Factorisation"}
           ] = preview.rows

    assert Decimal.equal?(hours, Decimal.new("4"))
  end

  test "reports duplicate week numbers during preview without blocking import", %{
    scope: scope,
    plan: plan,
    tenant: tenant,
    teacher: teacher
  } do
    Ash.create!(
      ProgressionEntry,
      %{progression_plan_id: plan.id, week_number: 1, title: "Existing", planned_hours: 4},
      tenant: tenant,
      actor: teacher,
      authorize?: false
    )

    configure_fake_pdftotext("""
    Week   Start        End          Lesson              Content          Hours
    1      2026-09-01   2026-09-05   Linear equations    Equations        4
    """)

    assert {:ok, %{rows: [%{duplicate?: true, errors: []}]}} =
             ProgressionImport.preview_rows(scope, plan.id, pdf_path())
  end

  test "saves reviewed rows append-only", %{scope: scope, plan: plan} do
    rows = [
      %{
        "week_number" => "1",
        "start_date" => "2026-09-01",
        "end_date" => "2026-09-05",
        "title" => "Linear equations",
        "planned_content" => "Solving first-degree equations",
        "planned_hours" => "4"
      },
      %{
        "week_number" => "1",
        "start_date" => "2026-09-08",
        "end_date" => "2026-09-12",
        "title" => "Duplicate imported week",
        "planned_content" => "Still appended",
        "planned_hours" => "2"
      }
    ]

    assert {:ok, saved} = ProgressionImport.save_rows(scope, plan.id, rows)
    assert length(saved.entries) == 2

    entries =
      ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan.id)
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(scope: scope)

    assert Enum.map(entries, & &1.title) == ["Linear equations", "Duplicate imported week"]
  end

  test "rejects invalid reviewed rows without saving any entries", %{scope: scope, plan: plan} do
    rows = [
      %{
        "week_number" => "",
        "title" => "",
        "planned_content" => "Missing required fields",
        "planned_hours" => "x"
      }
    ]

    assert {:error, {:invalid_rows, [%{errors: errors}]}} =
             ProgressionImport.save_rows(scope, plan.id, rows)

    assert "Week is required" in errors
    assert "Title is required" in errors
    assert "Hours must be a number" in errors

    assert [] =
             ProgressionEntry
             |> Ash.Query.filter(progression_plan_id == ^plan.id)
             |> Ash.read!(scope: scope)
  end

  test "returns a controlled error when pdftotext is missing", %{scope: scope, plan: plan} do
    Application.put_env(:teacher_assistant, :pdftotext_path, "/missing/pdftotext")

    assert {:error, :pdftotext_missing} =
             ProgressionImport.preview_rows(scope, plan.id, pdf_path())
  end

  test "blocks import into another teacher's plan", %{tenant: tenant, user: admin, scope: scope} do
    other_teacher = generate(user(tenant: tenant, role: :teacher))
    academic_year = generate(academic_year(tenant: tenant, actor: admin))
    level_option = generate(level_option(tenant: tenant, actor: admin))
    subject = generate(subject(tenant: tenant, actor: admin, name: "Physics"))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 4},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

    other_plan =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionPlan,
        %{
          academic_year_id: academic_year.id,
          classroom_id: classroom.id,
          level_option_subject_id: level_option_subject.id,
          teacher_id: other_teacher.id
        },
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    assert {:error, :plan_not_found} = ProgressionImport.save_rows(scope, other_plan.id, [])
  end

  defp configure_fake_pdftotext(output) do
    path =
      Path.join(System.tmp_dir!(), "teacher-assistant-fake-pdftotext-#{System.unique_integer()}")

    File.write!(path, "#!/bin/sh\ncat <<'EOF'\n#{output}\nEOF\n")
    File.chmod!(path, 0o755)
    Application.put_env(:teacher_assistant, :pdftotext_path, path)
  end

  defp pdf_path do
    path =
      Path.join(System.tmp_dir!(), "teacher-assistant-progression-#{System.unique_integer()}.pdf")

    File.write!(path, "%PDF fake")
    path
  end
end
