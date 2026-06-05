defmodule TeacherAssistantWeb.ProgressionWorkspaceLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  require Ash.Query

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.ProgressionEntry

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    teacher = generate(user(tenant: school, role: :teacher))

    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))
    generate(user_school(tenant: school, user_id: teacher.id, role: teacher.role))

    academic_year = generate(academic_year(tenant: school, actor: admin))
    level_option = generate(level_option(tenant: school, actor: admin))
    subject = generate(subject(tenant: school, actor: admin, name: "Mathematics"))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 4},
        authorize?: false
      )

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: school,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

    Ash.create!(
      TeacherAssistant.Academics.TeachingAssignment,
      %{
        classroom_id: classroom.id,
        level_option_subject_id: level_option_subject.id,
        teacher_id: teacher.id
      },
      tenant: school,
      actor: admin,
      authorize?: false
    )

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
        tenant: school,
        actor: admin,
        authorize?: false
      )

    entry =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionEntry,
        %{
          progression_plan_id: plan.id,
          term_id: hd(academic_year.terms).id,
          week_number: 1,
          start_date: Date.utc_today(),
          end_date: Date.add(Date.utc_today(), 4),
          title: "Linear equations",
          planned_content: "Solving first-degree equations",
          planned_hours: Decimal.new("4"),
          entry_type: :lesson
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :pdftotext_path)
    end)

    %{
      conn: log_in_user(conn, school, teacher),
      tenant: school,
      teacher: teacher,
      plan: plan,
      entry: entry
    }
  end

  test "teacher logs progression and creates an APC structure", %{
    conn: conn,
    tenant: tenant,
    teacher: teacher,
    plan: plan,
    entry: entry
  } do
    {:ok, view, _html} = live(conn, "/teacher/progression")

    assert has_element?(view, "#progression-plan-#{plan.id}")
    assert has_element?(view, "#progression-entry-#{entry.id}")
    assert has_element?(view, "#coverage-rate-#{plan.id}")

    assert view
           |> form("#teaching-log-form-#{entry.id}",
             teaching_log: %{
               taught_on: Date.to_iso8601(Date.utc_today()),
               taught_hours: "3",
               notes: "Exercises started"
             }
           )
           |> render_submit()

    log =
      TeacherAssistant.Academics.TeachingLog
      |> Ash.Query.filter(progression_entry_id == ^entry.id)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert Decimal.equal?(log.taught_hours, Decimal.new("3"))

    assert view
           |> form("#apc-lesson-form-#{entry.id}",
             apc_lesson_plan: %{
               competence: "Solve a real-life problem with first-degree equations",
               prerequisites: "Arithmetic operations",
               situation_problem: "Unknown unit price at the market",
               learning_activities: "Observe, model, solve, verify",
               resources: "Board, exercise sheet",
               evaluation: "Individual exercise",
               remediation: "Guided correction",
               duration_minutes: "55"
             }
           )
           |> render_submit()

    lesson =
      TeacherAssistant.Academics.ApcLessonPlan
      |> Ash.Query.filter(progression_entry_id == ^entry.id)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert lesson.competence =~ "real-life"
  end

  test "teacher imports a PDF progression into a reviewed draft table", %{conn: conn, plan: plan} do
    configure_fake_pdftotext("""
    Week   Start        End          Lesson                         Content                         Hours
    2      2026-09-08   2026-09-12   Factorisation                  Common factor and identities    3.5
    """)

    {:ok, view, _html} = live(conn, "/teacher/progression")

    assert has_element?(view, "#progression-import-form-#{plan.id}")

    upload =
      file_input(view, "#progression-import-form-#{plan.id}", :progression_pdf, [
        %{name: "progression.pdf", content: "%PDF fake", type: "application/pdf"}
      ])

    assert render_upload(upload, "progression.pdf")

    html =
      view
      |> element("#progression-import-form-#{plan.id}")
      |> render_submit(%{})

    assert html =~ "progression-import-review-#{plan.id}"
    assert html =~ "Factorisation"
  end

  test "teacher edits reviewed PDF rows before saving", %{
    conn: conn,
    plan: plan,
    tenant: tenant,
    teacher: teacher
  } do
    configure_fake_pdftotext("""
    Week   Start        End          Lesson                         Content                         Hours
    2      2026-09-08   2026-09-12   Factorisation                  Common factor and identities    3.5
    """)

    {:ok, view, _html} = live(conn, "/teacher/progression")

    upload =
      file_input(view, "#progression-import-form-#{plan.id}", :progression_pdf, [
        %{name: "progression.pdf", content: "%PDF fake", type: "application/pdf"}
      ])

    render_upload(upload, "progression.pdf")

    view
    |> element("#progression-import-form-#{plan.id}")
    |> render_submit(%{})

    assert view
           |> form("#progression-import-review-form-#{plan.id}",
             progression_import: %{
               rows: %{
                 "0" => %{
                   week_number: "2",
                   start_date: "2026-09-08",
                   end_date: "2026-09-12",
                   title: "Edited factorisation",
                   planned_content: "Edited content",
                   planned_hours: "3"
                 }
               }
             }
           )
           |> render_submit()

    entry =
      ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan.id and week_number == 2)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert entry.title == "Edited factorisation"
    assert Decimal.equal?(entry.planned_hours, Decimal.new("3"))
  end

  test "invalid reviewed PDF rows show row errors and are not saved", %{
    conn: conn,
    plan: plan,
    tenant: tenant
  } do
    configure_fake_pdftotext("""
    Week   Start        End          Lesson                         Content                         Hours
    2      2026-09-08   2026-09-12   Factorisation                  Common factor and identities    3.5
    """)

    {:ok, view, _html} = live(conn, "/teacher/progression")

    upload =
      file_input(view, "#progression-import-form-#{plan.id}", :progression_pdf, [
        %{name: "progression.pdf", content: "%PDF fake", type: "application/pdf"}
      ])

    render_upload(upload, "progression.pdf")

    view
    |> element("#progression-import-form-#{plan.id}")
    |> render_submit(%{})

    html =
      view
      |> form("#progression-import-review-form-#{plan.id}",
        progression_import: %{
          rows: %{
            "0" => %{
              week_number: "",
              title: "",
              planned_content: "Missing fields",
              planned_hours: "bad"
            }
          }
        }
      )
      |> render_submit()

    assert html =~ "Week is required"
    assert html =~ "Title is required"
    assert html =~ "Hours must be a number"

    entries =
      ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan.id and title == "Missing fields")
      |> Ash.read!(tenant: tenant)

    assert entries == []
  end

  test "personal teacher creates a progression plan and weekly entry", %{conn: conn} do
    teacher = generate(user_without_school(role: :teacher))
    workspace = Workspaces.ensure_personal_workspace!(teacher)
    scope = Workspaces.scope_for!(teacher, workspace.id)

    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    {:ok, view, _html} =
      conn
      |> log_in_user(workspace, teacher)
      |> live(~p"/teacher/progression")

    assert has_element?(view, "#progression-plan-form")

    assert view
           |> form("#progression-plan-form",
             progression_plan: %{
               assignment_id: setup.teaching_assignment.id,
               weekly_hours: "4",
               annual_hours: "96"
             }
           )
           |> render_submit()

    plan =
      TeacherAssistant.Academics.ProgressionPlan
      |> Ash.Query.filter(teacher_id == ^teacher.id)
      |> Ash.read_one!(scope: scope)

    assert has_element?(view, "#progression-plan-#{plan.id}")
    assert has_element?(view, "#progression-entry-form-#{plan.id}")
    assert has_element?(view, "#progression-import-form-#{plan.id}")

    configure_fake_pdftotext("""
    Week   Start        End          Lesson             Content        Hours
    2      2026-09-08   2026-09-12   Geometry basics    Angles         4
    """)

    upload =
      file_input(view, "#progression-import-form-#{plan.id}", :progression_pdf, [
        %{name: "personal-progression.pdf", content: "%PDF fake", type: "application/pdf"}
      ])

    render_upload(upload, "personal-progression.pdf")

    view
    |> element("#progression-import-form-#{plan.id}")
    |> render_submit(%{})

    assert view
           |> form("#progression-import-review-form-#{plan.id}",
             progression_import: %{
               rows: %{
                 "0" => %{
                   week_number: "2",
                   start_date: "2026-09-08",
                   end_date: "2026-09-12",
                   title: "Geometry basics",
                   planned_content: "Angles",
                   planned_hours: "4"
                 }
               }
             }
           )
           |> render_submit()

    imported_entry =
      TeacherAssistant.Academics.ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan.id and week_number == 2)
      |> Ash.read_one!(scope: scope)

    assert imported_entry.title == "Geometry basics"

    term = setup.academic_year |> Ash.load!(:terms, scope: scope) |> Map.fetch!(:terms) |> hd()

    assert view
           |> form("#progression-entry-form-#{plan.id}",
             progression_entry: %{
               term_id: term.id,
               week_number: "1",
               title: "Linear equations",
               planned_content: "Solving equations",
               planned_hours: "4",
               entry_type: "lesson"
             }
           )
           |> render_submit()

    entry =
      TeacherAssistant.Academics.ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan.id and week_number == 1)
      |> Ash.read_one!(scope: scope)

    assert has_element?(view, "#progression-entry-#{entry.id}")
  end

  defp configure_fake_pdftotext(output) do
    path =
      Path.join(
        System.tmp_dir!(),
        "teacher-assistant-live-fake-pdftotext-#{System.unique_integer()}"
      )

    File.write!(path, "#!/bin/sh\ncat <<'EOF'\n#{output}\nEOF\n")
    File.chmod!(path, 0o755)
    Application.put_env(:teacher_assistant, :pdftotext_path, path)
  end
end
