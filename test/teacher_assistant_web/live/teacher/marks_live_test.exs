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

    view
    |> form("#marks-form", %{"scores" => %{s1.id => "15"}})
    |> render_submit()

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

    html =
      view
      |> form("#marks-form", %{"scores" => %{s1.id => "25"}})
      |> render_submit()

    assert html =~ "0 and 20"
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

    view |> form("#marks-form", %{"scores" => %{s1.id => "13,5"}}) |> render_submit()

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

    html = view |> form("#marks-form", %{"scores" => %{s1.id => "abc"}}) |> render_submit()

    assert html =~ "valid"
    assert Assessment.list_marks(scope, a) == []
  end

  test "keeps unsaved marks when switching assessment and back", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, other} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 2"})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    # type a mark (unsaved) for assessment a
    view |> element("#marks-form") |> render_change(%{"scores" => %{s1.id => "14"}})

    # switch to another assessment, then back to a — without ever saving
    view |> element("#assessment-select") |> render_change(%{"assessment" => other.id})
    view |> element("#assessment-select") |> render_change(%{"assessment" => a.id})

    # the unsaved 14 is still in the input, not lost
    assert has_element?(view, "#mark-input-#{s1.id}[value='14']")
    assert Assessment.list_marks(scope, a) == []
  end

  test "mark inputs are debounced to avoid a round-trip per keystroke", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#mark-input-#{s1.id}[phx-debounce]")
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

    html =
      view
      |> element("#marks-form")
      |> render_change(%{"scores" => %{s1.id => "14", s2.id => "10"}})

    assert html =~ "2"
    # average preview: (14 + 10) / 2 = 12
    assert view |> element("#marks-average-preview") |> render() =~ "12"
  end

  test "toolbar wraps séquence and assessment controls", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-toolbar #seq-select")
    assert has_element?(view, "#marks-toolbar #assessment-select")
  end

  test "md sheet shows sibling assessment scores read-only", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, other} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 2"})

    :ok =
      Assessment.upsert_marks(scope, other, [
        %{student_id: s1.id, score: Decimal.new("17")}
      ])

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-sheet-header", "Devoir 2")
    assert render(element(view, "#mark-row-#{s1.id}")) =~ "17"
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
    assert has_element?(view, "#marks-sheet-header", "Composition")
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
end
