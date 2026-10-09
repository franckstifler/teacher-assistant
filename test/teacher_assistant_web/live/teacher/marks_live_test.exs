defmodule TeacherAssistantWeb.Teacher.MarksLiveTest do
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
    {:ok, a} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})
    %{ws: ws, ctx: ctx, seq: seq, a: a, s1: s1, cg: cg, scope: scope}
  end

  test "enters a mark for a student", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "15")

    assert [m] = Assessment.list_marks(scope, a)
    assert Decimal.equal?(m.score, Decimal.new("15"))
  end

  test "rejects an out-of-range mark with an error and saves nothing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "25")

    assert has_element?(view, "#mark-error-#{s1.id}", "Note entre 0 et 20")
    assert has_element?(view, "#mark-input-#{s1.id}[value='25']")
    assert has_element?(view, "#save-state", "1 note à corriger")
    assert Assessment.list_marks(scope, a) == []
  end

  test "accepts a French decimal comma", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "13,5")

    assert [m] = Assessment.list_marks(scope, a)
    assert Decimal.equal?(m.score, Decimal.new("13.5"))
  end

  test "rejects a non-numeric mark with an error and saves nothing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "abc")

    assert has_element?(view, "#mark-error-#{s1.id}", "Note entre 0 et 20")
    assert has_element?(view, "#mark-input-#{s1.id}[value='abc']")
    assert Assessment.list_marks(scope, a) == []

    # Correcting the cell clears its error.
    blur(view, s1.id, "11")
    refute has_element?(view, "#mark-error-#{s1.id}")
  end

  test "blur with an unchanged value does not write", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: Decimal.new(12)}])
    [before] = Assessment.list_marks(scope, a)

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "12,0")
    [after_blur] = Assessment.list_marks(scope, a)
    assert after_blur.updated_at == before.updated_at
    refute has_element?(view, "#save-state", "Enregistré")
  end

  test "each mark input saves on blur", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#mark-input-#{s1.id}[phx-blur='save_mark']")
    refute has_element?(view, "#marks-submit")
  end

  test "the absent toggle marks and unmarks", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    view |> element("#absent-#{s1.id}") |> render_click()
    assert [%{status: :absent, score: nil}] = Assessment.list_marks(scope, a)
    assert has_element?(view, "#mark-input-#{s1.id}[disabled]")
    assert has_element?(view, "#mark-appreciation-#{s1.id}", "Absent")

    view |> element("#absent-#{s1.id}") |> render_click()
    refute Enum.any?(Assessment.list_marks(scope, a), &(&1.status == :absent))
    refute has_element?(view, "#mark-input-#{s1.id}[disabled]")
  end

  test "a saved mark shows its appreciation and « Enregistré »", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "15")

    expected =
      TeacherAssistant.Academics.Marks.mention(Decimal.new(15), Assessment.grading_rules(scope))

    assert has_element?(view, "#mark-appreciation-#{s1.id}", expected.label)
    assert has_element?(view, "#save-state", "Enregistré")
  end

  test "a mark under 10/20 shows in red", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    blur(view, s1.id, "8")
    assert has_element?(view, "#mark-input-#{s1.id}.text-error")
  end

  test "without ?seq= the current séquence is open, its assessments listed", %{
    conn: conn,
    ctx: ctx
  } do
    {:ok, view, html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks")

    # The test clock (2025-09-15) is inside the first séquence, where « Devoir 1 » is.
    assert html =~ "Devoir 1"
    assert has_element?(view, "#new-assessment-form")
  end

  test "unknown teaching context redirects to /school", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/marks")
  end

  test "each score input has the student name as its accessible label", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#mark-input-#{s1.id}[aria-label='#{s1.full_name}']")
  end

  test "shows entry progress and live average preview", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    cg: cg,
    scope: scope
  } do
    {:ok, s2} = Enrollment.add_student(scope, cg, %{full_name: "Beba", sex: :m})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-progress")

    blur(view, s1.id, "14")
    blur(view, s2.id, "10")

    assert view |> element("#marks-progress") |> render() =~ "2"
    # average preview: (14 + 10) / 2 = 12
    assert view |> element("#marks-average-preview") |> render() =~ "12"
  end

  test "toolbar wraps séquence and assessment controls", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-toolbar #seq-select")
    assert has_element?(view, "#marks-toolbar #assessment-select")
  end

  test "creating an assessment in solo mode creates it and selects it", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Composition"}})
    |> render_submit()

    assert Enum.any?(Assessment.list_assessments(scope, ctx, seq), &(&1.label == "Composition"))
    # the newly created assessment is now the selected column — its sheet renders
    assert has_element?(view, "#marks-table thead", "Composition")
  end

  test "a blank assessment label is rejected and creates nothing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    scope: scope
  } do
    existing = Assessment.list_assessments(scope, ctx, seq)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => ""}})
    |> render_submit()

    # {:error, form} branch: nothing persisted, the toolbar form stays put
    assert Assessment.list_assessments(scope, ctx, seq) == existing
    assert has_element?(view, "#new-assessment-form")
  end

  test "shows the séquence's grade-entry deadline", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(
             view,
             "#entry-deadline",
             Calendar.strftime(seq.grade_entry_deadline, "%d/%m/%Y")
           )
  end

  defp blur(view, student_id, value),
    do: view |> element("#mark-input-#{student_id}") |> render_blur(%{"value" => value})
end
