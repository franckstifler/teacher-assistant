defmodule TeacherAssistant.Academics.ProgressionPlanUnitTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.{Academics, TeacherFixtures}

  setup do
    user = TeacherFixtures.user_fixture()
    ws = TeacherFixtures.workspace_fixture(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, course} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Maths",
        label: "Maths · combined",
        workspace_id: ws.id,
        academic_year_id: year.id,
        teacher_user_id: user.id
      })
      |> Ash.create(authorize?: false)

    %{ws: ws, year: year, ctx: ctx, course: course}
  end

  test "a plan can belong to a combined course", %{course: course} do
    {:ok, plan} = Academics.create_course_plan(course, %{title: "Maths"})
    assert plan.combined_course_id == course.id
    assert is_nil(plan.teaching_context_id)
    assert plan.workspace_id == course.workspace_id
    assert plan.academic_year_id == course.academic_year_id
  end

  test "a plan created from a teaching context has no combined_course_id", %{ctx: ctx} do
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})
    assert plan.teaching_context_id == ctx.id
    assert is_nil(plan.combined_course_id)
  end

  test "create_course_plan defaults title and academic_year_id from the course", %{
    course: course
  } do
    {:ok, plan} = Academics.create_course_plan(course, %{})
    assert plan.title == course.subject
    assert plan.academic_year_id == course.academic_year_id
  end
end
