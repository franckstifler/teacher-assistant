defmodule TeacherAssistantWeb.Teacher.MarksLockTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.MarksFixtures

  setup %{conn: conn} do
    world = MarksFixtures.marks_world()

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    conn =
      conn
      |> log_in_user(world.t.current_user)
      |> Plug.Conn.put_session(:workspace_id, world.head.current_workspace.id)

    path = ~p"/teacher/contexts/#{world.tc.id}/marks?seq=#{world.seq.id}&assessment=#{world.a.id}"
    Map.merge(world, %{conn: conn, path: path})
  end

  test "an open séquence is editable", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    refute has_element?(view, "#locked-banner")
    assert has_element?(view, "#new-assessment-form")
    refute has_element?(view, "#mark-input-#{ctx.s1.id}[disabled]")
  end

  test "a locked séquence is read-only and points to a correction request", ctx do
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))
    {:ok, view, _} = live(ctx.conn, ctx.path)

    assert view |> element("#locked-banner") |> render() =~ "verrouillée"

    assert has_element?(
             view,
             "#locked-request-link[href='/school/corrections/new?assessment=#{ctx.a.id}']"
           )

    assert has_element?(view, "#seq-tab-#{ctx.seq.id}", "verrouillée")
    refute has_element?(view, "#open-banner")
    assert has_element?(view, "#mark-input-#{ctx.s1.id}[disabled]")
    assert has_element?(view, "#absent-#{ctx.s1.id}[disabled]")
    refute has_element?(view, "#new-assessment-form")

    html = render_hook(view, "save_mark", %{"student" => ctx.s1.id, "value" => "3"})
    assert html =~ "Séquence verrouillée."
    render_hook(view, "toggle_absent", %{"student" => ctx.s1.id})
    [mark] = Assessment.list_marks(ctx.head, ctx.a)
    assert Decimal.equal?(mark.score, 12)
  end

  test "a combined course with a class missing an assessment shows a locked séquence", ctx do
    alias TeacherAssistant.{Curriculum, Enrollment}

    {:ok, cg2} =
      Enrollment.create_class_group(ctx.head, ctx.year, %{label: "6e Z", level: "6ème"})

    {:ok, tc2} =
      Curriculum.assign_teacher(ctx.head, cg2, ctx.t.current_user, %{subject: ctx.tc.subject})

    {:ok, course} = Curriculum.combine_course(ctx.head, [ctx.tc, tc2])
    # `Devoir 1` exists in the first class only; the second would need a backfill.
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))

    {:ok, view, _} =
      live(ctx.conn, ~p"/teacher/contexts/#{ctx.tc.id}/marks?seq=#{ctx.seq.id}")

    assert has_element?(view, "#locked-banner")
    assert [%{label: "Devoir 1"}] = Assessment.combined_assessments_for(ctx.t, course, ctx.seq)
  end

  test "an open séquence backfills a missing member-class assessment", ctx do
    alias TeacherAssistant.{Curriculum, Enrollment}

    {:ok, cg2} =
      Enrollment.create_class_group(ctx.head, ctx.year, %{label: "6e Y", level: "6ème"})

    {:ok, tc2} =
      Curriculum.assign_teacher(ctx.head, cg2, ctx.t.current_user, %{subject: ctx.tc.subject})

    {:ok, course} = Curriculum.combine_course(ctx.head, [ctx.tc, tc2])

    assert [%{by_class_group_id: by_class}] =
             Assessment.combined_assessments_for(ctx.t, course, ctx.seq)

    assert %{label: "Devoir 1"} = by_class[cg2.id]
  end

  test "a séquence locking while the page is open says so and shows the correction link", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))

    html = view |> element("#mark-input-#{ctx.s1.id}") |> render_blur(%{"value" => "15"})

    assert html =~ "Séquence verrouillée."
    assert has_element?(view, "#locked-banner")
    assert has_element?(view, "#mark-input-#{ctx.s1.id}[disabled]")
    [mark] = Assessment.list_marks(ctx.head, ctx.a)
    assert Decimal.equal?(mark.score, 12)
  end

  test "a séquence not started yet is read-only and says when entry opens", ctx do
    [_first, next | _] = TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year)

    {:ok, view, _} =
      live(ctx.conn, ~p"/teacher/contexts/#{ctx.tc.id}/marks?seq=#{next.id}")

    assert has_element?(view, "#upcoming-banner", "La saisie ouvre le")
    assert has_element?(view, "#seq-tab-#{next.id}", "à venir")
    refute has_element?(view, "#open-banner")
    refute has_element?(view, "#locked-banner")
    refute has_element?(view, "#new-assessment-form")

    html = render_hook(view, "new_assessment", %{"assessment" => %{"label" => "Devoir 1"}})
    assert html =~ "La saisie de cette séquence n&#39;est pas encore ouverte."
    assert Assessment.list_assessments(ctx.t, ctx.tc, next) == []
  end

  test "on a phone the séquence picker patches the page; another course opens its own", ctx do
    [_first, next | _] = TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year)
    {:ok, view, _} = live(ctx.conn, ctx.path)

    assert has_element?(view, "#pick-seq option[selected]", "Séquence #{ctx.seq.number}")
    # one course: no course picker
    refute has_element?(view, "#pick-course")

    view
    |> element("#marks-pickers")
    |> render_change(%{"_target" => ["seq"], "seq" => next.id})

    assert_patch(view, ~p"/teacher/contexts/#{ctx.tc.id}/marks?seq=#{next.id}")
    assert has_element?(view, "#upcoming-banner")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("#marks-pickers")
             |> render_change(%{"_target" => ["context"], "context" => "other", "seq" => next.id})

    assert to == "/teacher/contexts/other/marks?seq=#{next.id}"
  end
end
