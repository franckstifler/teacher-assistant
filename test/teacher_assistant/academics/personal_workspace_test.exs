defmodule TeacherAssistant.Academics.PersonalWorkspaceTest do
  use TeacherAssistant.DataCase

  require Ash.Query

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.PersonalWorkspace

  setup do
    teacher = generate(user_without_school(role: :teacher))
    personal = Workspaces.ensure_personal_workspace!(teacher)
    scope = Workspaces.scope_for!(teacher, personal.id)

    %{teacher: teacher, personal: personal, personal_scope: scope}
  end

  test "creates the private setup chain for a personal teacher workspace", %{
    personal_scope: scope,
    teacher: teacher
  } do
    params = %{
      "academic_year_name" => "2026-2027",
      "start_date" => "2026-09-01",
      "end_date" => "2027-06-30",
      "class_name" => "Form 5",
      "option_name" => "Science",
      "subject_name" => "Mathematics",
      "coefficient" => "4",
      "students" => [
        %{"first_name" => "Ada", "last_name" => "Nanga", "gender" => "female"},
        %{"first_name" => "Jean", "last_name" => "Meka", "gender" => "male"}
      ]
    }

    assert {:ok, setup} = PersonalWorkspace.create_setup(scope, params)

    assert setup.academic_year.name == "2026-2027"
    assert setup.classroom.academic_year_id == setup.academic_year.id
    assert setup.level.name == "Form 5"
    assert to_string(setup.option.name) == "Science"
    assert setup.subject.name == "Mathematics"
    assert setup.level_option_subject.coefficient == 4
    assert setup.teaching_assignment.teacher_id == teacher.id
    assert length(setup.students) == 2

    [term | _] = Ash.load!(setup.academic_year, [terms: [:sequences]], scope: scope).terms
    assert term.name == "Term 1"
    assert length(term.sequences) == 2
  end

  test "rejects personal setup from a school teacher workspace", %{teacher: teacher} do
    school = generate(school())
    generate(user_school(tenant: school, user_id: teacher.id, role: :teacher))
    school_scope = Workspaces.scope_for!(teacher, school.id)

    assert {:error, :personal_workspace_required} =
             PersonalWorkspace.create_setup(school_scope, %{
               "academic_year_name" => "2026-2027",
               "start_date" => "2026-09-01",
               "end_date" => "2027-06-30",
               "class_name" => "Form 5",
               "option_name" => "Science",
               "subject_name" => "Mathematics"
             })
  end

  test "uses the personal workspace tenant even when the teacher also belongs to a school", %{
    teacher: teacher,
    personal: personal,
    personal_scope: scope
  } do
    school = generate(school())
    generate(user_school(tenant: school, user_id: teacher.id, role: :teacher))

    assert {:ok, setup} =
             PersonalWorkspace.create_setup(scope, %{
               "academic_year_name" => "2026-2027",
               "start_date" => "2026-09-01",
               "end_date" => "2027-06-30",
               "class_name" => "Form 5",
               "option_name" => "Science",
               "subject_name" => "Mathematics"
             })

    assert setup.academic_year.school_id == personal.id
    refute setup.academic_year.school_id == school.id
  end

  test "returns a controlled error when the personal academic year name already exists", %{
    personal_scope: scope
  } do
    params = %{
      "academic_year_name" => "2026-2027",
      "start_date" => "2026-09-01",
      "end_date" => "2027-06-30",
      "class_name" => "Form 5",
      "option_name" => "Science",
      "subject_name" => "Mathematics"
    }

    assert {:ok, _setup} = PersonalWorkspace.create_setup(scope, params)
    assert {:error, :academic_year_already_exists} = PersonalWorkspace.create_setup(scope, params)
  end

  test "imports valid CSV rows into a selected personal classroom and reports invalid rows", %{
    personal_scope: scope
  } do
    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    csv = """
    first_name,last_name,matricule,gender,date_of_birth,place_of_birth
    Alice,Fotso,A001,female,2011-04-03,Bamenda
    Missing Last,,A002,male,2010-01-01,Douala
    Paul,Tamo,A003,male,,Yaounde
    """

    assert {:ok, result} = PersonalWorkspace.import_students(scope, setup.classroom.id, csv)
    assert length(result.created) == 2
    assert [%{row: 3, errors: [_ | _]}] = result.invalid

    classroom_students =
      Academics.ClassroomStudent
      |> Ash.Query.filter(classroom_id == ^setup.classroom.id)
      |> Ash.read!(scope: scope)

    assert length(classroom_students) == 2
  end

  test "creates a personal progression plan and weekly entry for the current teacher", %{
    personal_scope: scope,
    teacher: teacher
  } do
    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    assert {:ok, plan} =
             PersonalWorkspace.create_progression_plan(scope, %{
               "academic_year_id" => setup.academic_year.id,
               "classroom_id" => setup.classroom.id,
               "level_option_subject_id" => setup.level_option_subject.id,
               "weekly_hours" => "4",
               "annual_hours" => "96"
             })

    assert plan.teacher_id == teacher.id

    term = setup.academic_year |> Ash.load!(:terms, scope: scope) |> Map.fetch!(:terms) |> hd()

    assert {:ok, entry} =
             PersonalWorkspace.create_progression_entry(scope, plan.id, %{
               "term_id" => term.id,
               "week_number" => "1",
               "title" => "Linear equations",
               "planned_content" => "Solving equations",
               "planned_hours" => "4",
               "entry_type" => "lesson"
             })

    assert entry.progression_plan_id == plan.id
    assert entry.title == "Linear equations"
  end
end
