defmodule TeacherAssistant.Academics.ProgressionPlanUnitTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.{CombinedCourse, ProgressionPlan}
  alias TeacherAssistant.{Curriculum, TeacherFixtures}

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    {:ok, course} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Maths",
        label: "Maths · combined",
        workspace_id: ws.id,
        academic_year_id: year.id,
        teacher_user_id: head.id
      })
      |> Ash.create(authorize?: false)

    %{ws: ws, year: year, ctx: ctx, course: course}
  end

  test "a plan can belong to a combined course", %{course: course} do
    {:ok, plan} = Curriculum.create_course_plan(course, %{title: "Maths"})
    assert plan.combined_course_id == course.id
    assert is_nil(plan.teaching_context_id)
    assert plan.workspace_id == course.workspace_id
    assert plan.academic_year_id == course.academic_year_id
  end

  test "a plan created from a teaching context has no combined_course_id", %{ctx: ctx} do
    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Maths 6ème"})
    assert plan.teaching_context_id == ctx.id
    assert is_nil(plan.combined_course_id)
  end

  test "create_course_plan defaults title and academic_year_id from the course", %{
    course: course
  } do
    {:ok, plan} = Curriculum.create_course_plan(course, %{})
    assert plan.title == course.subject
    assert plan.academic_year_id == course.academic_year_id
  end

  describe "exactly one owner validation" do
    test "create fails when neither teaching_context_id nor combined_course_id is set", %{
      ws: ws,
      year: year
    } do
      assert {:error, error} =
               ProgressionPlan
               |> Ash.Changeset.for_create(:create, %{
                 title: "Orphan",
                 academic_year_id: year.id,
                 workspace_id: ws.id
               })
               |> Ash.create(authorize?: false)

      assert error_on_field?(error, :teaching_context_id)
    end

    test "create fails when both teaching_context_id and combined_course_id are set", %{
      ws: ws,
      year: year,
      ctx: ctx,
      course: course
    } do
      assert {:error, error} =
               ProgressionPlan
               |> Ash.Changeset.for_create(:create, %{
                 title: "Double owner",
                 academic_year_id: year.id,
                 workspace_id: ws.id,
                 teaching_context_id: ctx.id,
                 combined_course_id: course.id
               })
               |> Ash.create(authorize?: false)

      assert error_on_field?(error, :teaching_context_id)
    end

    test "create succeeds when exactly one owner FK is set", %{ctx: ctx, course: course} do
      assert {:ok, _plan} = Curriculum.create_progression_plan(ctx, %{title: "Solo"})
      assert {:ok, _plan} = Curriculum.create_course_plan(course, %{title: "Combined"})
    end

    defp error_on_field?(%{errors: errors}, field) do
      Enum.any?(errors, fn error -> Map.get(error, :field) == field end)
    end
  end
end
