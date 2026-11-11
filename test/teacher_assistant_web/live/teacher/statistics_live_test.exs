defmodule TeacherAssistantWeb.Teacher.StatisticsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head, scope: scope, year: year} do
    scope = %{scope | current_academic_year: year}
    [seq | _] = Organization.list_sequences(scope, year)

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})

    {:ok, maths} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, phys} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Physique"})

    marks(scope, maths, seq, %{awa => 15, bob => 7})
    marks(scope, phys, seq, %{awa => 11, bob => 12})

    %{teacher: teacher, scope: teacher_scope} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "SVT"})

    %{
      scope: scope,
      seq: seq,
      cg: cg,
      maths: maths,
      phys: phys,
      teacher: teacher,
      teacher_scope: teacher_scope,
      awa: awa,
      bob: bob,
      year: year
    }
  end

  defp marks(scope, tc, seq, scores) do
    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{label: "Devoir", max_score: Decimal.new(20)})

    :ok =
      Assessment.upsert_marks(
        scope,
        a,
        Enum.map(scores, fn {st, v} -> %{student_id: st.id, score: Decimal.new(v)} end)
      )
  end

  defp conn_for(%{workspace: ws}, user) do
    Phoenix.ConnTest.build_conn()
    |> log_in_user(user)
    |> Plug.Conn.put_session(:workspace_id, ws.id)
  end

  test "lists every course of the teacher for the current séquence", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/statistics/me")

    assert has_element?(view, "#stats-table")
    assert has_element?(view, "#stats-table tbody tr[data-course]", "Maths")
    assert has_element?(view, "#stats-table tbody tr[data-course]", "Physique")

    stats = Assessment.course_statistics(ctx.scope, ctx.maths, {:sequence, ctx.seq})
    assert Decimal.equal?(stats.summary.class_average, 11)
    assert has_element?(view, "#stats-row-#{ctx.maths.id} [data-col=average]", "11")
    assert has_element?(view, "#stats-row-#{ctx.maths.id} [data-col=pass]", "50 %")
    assert has_element?(view, "#stats-row-#{ctx.maths.id} [data-col=pass-f]", "100 %")
    assert has_element?(view, "#stats-row-#{ctx.maths.id} [data-col=pass-m]", "0 %")
  end

  test "the period selector patches to a trimester and shows its status line", ctx do
    [term | _] = Organization.list_terms(ctx.scope, ctx.year)
    {:ok, view, _} = live(ctx.conn, ~p"/school/statistics/me")

    view |> element("#stats-period-trim-#{term.id}") |> render_click()
    assert has_element?(view, "#stats-period-trim-#{term.id}[aria-current='true']")
    assert has_element?(view, "#stats-source", "provisoires")
    assert has_element?(view, "#stats-row-#{ctx.maths.id}")
  end

  test "a combined course is one row plus a sub-row per class", ctx do
    {:ok, cg_b} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    {:ok, _} = Enrollment.add_student(ctx.scope, cg_b, %{full_name: "Cléo", sex: :f})
    {:ok, maths_b} = Curriculum.assign_teacher(ctx.scope, cg_b, ctx.actor, %{subject: "Maths"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [ctx.maths, maths_b])

    {:ok, view, _} = live(ctx.conn, ~p"/school/statistics/me")
    assert has_element?(view, "#stats-row-combined-#{course.id}[data-course]")
    assert has_element?(view, "#stats-table tr[data-class]", "6e A")
    assert has_element?(view, "#stats-table tr[data-class]", "6e B")
  end

  test "a plain teacher cannot read another teacher's statistics", ctx do
    conn = conn_for(ctx, ctx.teacher)
    {:ok, view, _} = live(conn, ~p"/school/statistics/me?teacher=#{ctx.actor.id}")

    assert render(view) =~ "autorisation"
    refute has_element?(view, "#stats-table", "Maths")
    assert has_element?(view, "#stats-table", "SVT")
  end

  test "the head opens a teacher's page by id and sees their name", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/statistics/me?teacher=#{ctx.teacher.id}")

    assert has_element?(view, "h1", "Statistiques")
    assert has_element?(view, "#stats-table", "SVT")
    refute has_element?(view, "#stats-table", "Maths")
    assert view |> element("#stats-print") |> render() =~ "teacher=#{ctx.teacher.id}"
  end

  test "a teacher without course sees the empty state", ctx do
    other = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, view, _} = live(conn_for(ctx, other.current_user), ~p"/school/statistics/me")
    assert has_element?(view, "#stats-empty")
  end

  test "a period whose séquences have not all started is labelled « en cours » (minors)", ctx do
    %{conn: conn, scope: scope, seq: seq, year: year} = ctx
    started? = &(not TeacherAssistant.Academics.Lock.not_started?(&1))
    assert Enum.any?(Organization.list_sequences(scope, year), &(not started?.(&1)))

    {:ok, view, _} = live(conn, ~p"/school/statistics/me?period=annee")
    assert has_element?(view, "#stats-in-progress", "En cours")

    param = Organization.period_param({:sequence, seq})
    {:ok, view, _} = live(conn, ~p"/school/statistics/me?period=#{param}")
    refute has_element?(view, "#stats-in-progress")
  end
end
