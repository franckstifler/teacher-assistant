defmodule TeacherAssistantWeb.Teacher.MarksSummaryLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  setup %{workspace: ws, year: year, actor: head, scope: scope} do
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    seq = Organization.list_sequences(scope, year) |> List.first()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    {:ok, cg} = Enrollment.fetch_owned_class_group(scope, ctx.class_group_id)
    {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})

    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: s1.id, score: Decimal.new("14")},
        %{student_id: s2.id, score: Decimal.new("8")}
      ])

    %{ws: ws, ctx: ctx, seq: seq, cg: cg, s1: s1, s2: s2, scope: scope}
  end

  test "shows class average and pass rate", %{conn: conn, ctx: ctx, seq: seq, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert has_element?(view, "#teacher-marks-summary")
    # class average (14 + 8) / 2 = 11
    assert has_element?(view, "#summary-class-average", "11")
    # pass rate: 1 of 2 students >= 10 => 50%
    assert has_element?(view, "#summary-pass-rate", "50")
    assert has_element?(view, "#summary-row-#{s1.id}", "Awa")
    assert has_element?(view, "#summary-row-#{s1.id}", "14")
  end

  test "ungraded student is not badged as failing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg,
    s2: s2,
    scope: scope
  } do
    {:ok, ungraded} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    # ungraded student shows "—" and no mention, never in coral
    ungraded_row = render(element(view, "#summary-row-#{ungraded.id}"))
    assert ungraded_row =~ "—"
    assert ungraded_row =~ "Pas de note"
    refute ungraded_row =~ "text-error"

    # graded failing student (score 8 < 10) carries its band, in coral
    s2_row = render(element(view, "#summary-row-#{s2.id}"))
    assert s2_row =~ "Médiocre"
    assert s2_row =~ "text-error"
  end

  test "shows mention distribution, sex bars and missing-marks line", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg,
    scope: scope
  } do
    {:ok, _ungraded} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    # Awa 14 => Bien; Beba 8 => Médiocre
    assert render(element(view, "#summary-mentions")) =~ "Bien"
    assert render(element(view, "#summary-mentions")) =~ "Médiocre"
    assert has_element?(view, "#summary-sex", "Réussite filles 100 % · garçons 0 %")
    # 1 of 3 students has no marks
    assert has_element?(view, "#summary-missing", "1")
  end

  test "séquence switcher patches to the chosen séquence", %{conn: conn, ctx: ctx, scope: scope} do
    year = Organization.current_academic_year(scope)
    seq2 = Organization.list_sequences(scope, year) |> Enum.at(1)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary")

    assert has_element?(view, "#summary-seq-#{seq2.id}", "Séq. #{seq2.number} · ")
    view |> element("#summary-seq-#{seq2.id}") |> render_click()

    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq2.id}")
    # séquence 2 has no assessments -> guided empty state, not stats
    refute has_element?(view, "#summary-class-average")
    assert render(view) =~ "Pas encore de notes dans cette séquence"
  end

  test "renders a table with rank and mention columns", %{conn: conn, ctx: ctx, seq: seq, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert has_element?(view, "#summary-table")
    row = render(element(view, "#summary-row-#{s1.id}"))
    assert row =~ "Awa"
    assert row =~ "14"
    assert row =~ "Bien"
  end

  test "unknown teaching context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks/summary")
  end

  test "shows the distribution bars and the way back to entry", %{conn: conn, ctx: ctx, seq: seq} do
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")
    assert has_element?(view, "#summary-distribution [data-band='12 – 15']", "1")
    assert has_element?(view, "#summary-distribution [data-band='5 – 10']", "1")
    assert has_element?(view, "#summary-distribution [data-band='0 – 5']", "0")
    assert has_element?(view, "#teacher-marks-summary h1", "Maths")
    assert has_element?(view, "#teaching-nav-marks[href^='/teacher/contexts/#{ctx.id}/marks']")
    assert has_element?(view, "#teaching-nav-back-arrow[href='/school/courses']")
  end

  test "ranks read as ordinals, the ranking sorts A → Z, the range reads min → max", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    s1: s1,
    s2: s2
  } do
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")
    assert has_element?(view, "#summary-row-#{s1.id}", "1er")
    assert has_element?(view, "#summary-row-#{s2.id}", "2e")
    assert has_element?(view, "#summary-range", "8 → 14")
    assert has_element?(view, "#sort-rank[aria-pressed='true']")

    view |> element("#sort-az") |> render_click()
    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}&sort=az")
    assert has_element?(view, "#sort-az[aria-pressed='true']")
  end

  test "a combined course gathers every member class, each row naming its class", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg,
    scope: scope
  } do
    year = Organization.current_academic_year(scope)

    ctx_b =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: scope.current_user
      })

    {:ok, cg_b} = Enrollment.fetch_owned_class_group(scope, ctx_b.class_group_id)
    {:ok, s3} = Enrollment.add_student(scope, cg_b, %{full_name: "Chloé", sex: :f})
    {:ok, a_b} = Assessment.create_assessment(scope, ctx_b, seq, %{label: "Devoir 1"})
    :ok = Assessment.upsert_marks(scope, a_b, [%{student_id: s3.id, score: Decimal.new("17")}])
    {:ok, _course} = TeacherAssistant.Curriculum.combine_course(scope, [ctx, ctx_b])

    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")
    assert has_element?(view, "#summary-row-#{s3.id}", "1er")
    assert has_element?(view, "#summary-row-#{s3.id}", cg_b.label)
    assert has_element?(view, "#summary-range", "8 → 17")
    assert has_element?(view, "#summary-table", cg.label)
  end
end
