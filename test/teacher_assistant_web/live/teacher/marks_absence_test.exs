defmodule TeacherAssistantWeb.Teacher.MarksAbsenceTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée M"})

    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e M", level: "4ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, a} = Assessment.create_assessment(scope, tc, seq, %{label: "D1"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    path = ~p"/teacher/contexts/#{tc.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
    %{conn: conn, scope: scope, tc: tc, seq: seq, a: a, awa: awa, bob: bob, path: path}
  end

  test "abs and abj are saved as absences, blank as not entered", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "ABS", ctx.bob.id => "abj"}})
    |> render_submit()

    by_student = Map.new(Assessment.list_marks(ctx.scope, ctx.a), &{&1.student_id, &1.status})
    assert by_student == %{ctx.awa.id => :absent, ctx.bob.id => :excused}
    assert has_element?(view, "#mark-input-#{ctx.awa.id}[value='abs']")

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "", ctx.bob.id => "abj"}})
    |> render_submit()

    assert [%{status: :excused}] = Assessment.list_marks(ctx.scope, ctx.a)
  end

  test "an unknown code rejects the whole batch", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "12", ctx.bob.id => "abx"}})
    |> render_submit()

    assert Assessment.list_marks(ctx.scope, ctx.a) == []
  end

  test "a new assessment takes its type's weight and the school's maximum", ctx do
    [ie | _] = Assessment.list_assessment_types(ctx.scope)
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#new-assessment-form", %{
      "assessment" => %{"assessment_type_id" => ie.id, "label" => "IE 1", "max_score" => "10"}
    })
    |> render_submit()

    created =
      Enum.find(Assessment.list_assessments(ctx.scope, ctx.tc, ctx.seq), &(&1.label == "IE 1"))

    assert Decimal.equal?(created.weight, Decimal.new("0.5"))
    assert Decimal.equal?(created.max_score, 10)
  end

  test "exempt students are not listed", ctx do
    subject = Enum.find(Curriculum.list_subjects(ctx.scope), &(&1.id == ctx.tc.subject_id))
    :ok = Curriculum.update_coefficient_grid(ctx.scope, %{"optional" => %{subject.id => "true"}})
    :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    {:ok, view, _} = live(ctx.conn, ctx.path)
    assert has_element?(view, "#mark-row-#{ctx.awa.id}")
    refute has_element?(view, "#mark-row-#{ctx.bob.id}")
  end

  test "under the make-up rule, absent students are listed as pending", ctx do
    {:ok, _} = Assessment.update_grading_rules(ctx.scope, %{"absence_rule" => "makeup"})

    :ok =
      Assessment.upsert_marks(ctx.scope, ctx.a, [
        %{student_id: ctx.awa.id, score: nil, status: :absent}
      ])

    {:ok, view, _} = live(ctx.conn, ctx.path)
    assert has_element?(view, "#pending-makeups", "Awa")
  end

  test "saving a stale page never touches marks the teacher did not edit", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    # Someone else enters Bob's mark after this page was loaded.
    :ok = Assessment.upsert_marks(ctx.scope, ctx.a, [%{student_id: ctx.bob.id, score: Decimal.new(14)}])

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "12", ctx.bob.id => ""}})
    |> render_submit()

    by_student = Map.new(Assessment.list_marks(ctx.scope, ctx.a), &{&1.student_id, &1.score})
    assert Decimal.equal?(by_student[ctx.awa.id], 12)
    assert Decimal.equal?(by_student[ctx.bob.id], 14)
  end
end
