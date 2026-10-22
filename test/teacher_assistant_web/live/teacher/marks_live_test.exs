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

  test "the blur a disabled absent cell may fire never clears the absence", %{
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
    render_hook(view, "save_mark", %{"student" => s1.id, "value" => ""})
    assert [%{status: :absent}] = Assessment.list_marks(scope, a)
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

    assert has_element?(view, "#marks-toolbar #seq-tabs")
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

  test "open banner names the deadline", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#open-banner", "Saisie ouverte jusqu'au")
    assert has_element?(view, "#open-banner", "dès que vous quittez la case")
  end

  test "course tabs link to the teacher's other courses", %{
    conn: conn,
    ctx: ctx,
    scope: scope,
    year: year,
    actor: head
  } do
    other =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Physique",
        level: "4ème",
        teacher: head
      })

    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks")
    assert has_element?(view, "#course-tabs a[href^='/teacher/contexts/#{other.id}/marks']")
    assert has_element?(view, "#course-tabs [aria-current='page']")
  end

  test "séquence tabs name their state and switch the séquence", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    scope: scope,
    year: year
  } do
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")
    assert has_element?(view, "#seq-tab-#{seq.id}", "Séquence #{seq.number} · ouverte")

    [_, seq2 | _] = Organization.list_sequences(scope, year)
    view |> element("#seq-tab-#{seq2.id}") |> render_click()
    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq2.id}")
  end

  test "the side panel counts what is left before the deadline", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a
  } do
    {:ok, view, _} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-missing", "1 note à saisir avant le")
    assert has_element?(view, "#marks-shortcuts", "Entrée")
  end

  test "the grid carries the shortcuts hook", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-table[phx-hook$='MarksGrid']")
  end

  defp blur(view, student_id, value),
    do: view |> element("#mark-input-#{student_id}") |> render_blur(%{"value" => value})

  test "on an unverified school a blur that changes nothing flashes nothing", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    operator = TeacherFixtures.admin_user_fixture()
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      TeacherAssistant.Accounts.reject_school(profile, operator.id, "test", actor: operator)

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    refute blur(view, s1.id, "") =~ "en attente de vérification"
    assert blur(view, s1.id, "12") =~ "en attente de vérification"
  end

  test "the Absent toggle keeps its label, asks before replacing a mark, links errors", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    a: a,
    s1: s1,
    scope: scope
  } do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    refute has_element?(view, "#absent-#{s1.id}[data-confirm]")
    blur(view, s1.id, "14")
    assert has_element?(view, "#absent-#{s1.id}[data-confirm]")

    view |> element("#absent-#{s1.id}") |> render_click()
    assert [%{status: :absent}] = Assessment.list_marks(scope, a)
    assert has_element?(view, "#absent-#{s1.id}[aria-pressed='true']", "Absent")

    view |> element("#absent-#{s1.id}") |> render_click()
    blur(view, s1.id, "25")

    assert has_element?(
             view,
             "#mark-input-#{s1.id}[aria-describedby='mark-error-#{s1.id}']"
           )
  end

  test "switching assessment with an uncorrected cell warns that its text is dropped", %{
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

    blur(view, s1.id, "25")
    html = view |> element("#assessment-select") |> render_change(%{"assessment" => other.id})
    assert html =~ "1 note non enregistrée abandonnée"
  end

  describe "APC competence (bulletin v2)" do
    defp apc_on(scope) do
      {:ok, _} =
        Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })
    end

    test "APC on: competence field above the marks and a reminder while empty", %{
      conn: conn,
      ctx: ctx,
      seq: seq,
      scope: scope
    } do
      apc_on(scope)
      {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")

      assert has_element?(view, "#sequence-competence")
      assert has_element?(view, "#competence-reminder")

      view
      |> form("#sequence-competence", %{competence: %{text: "Résoudre une équation"}})
      |> render_submit()

      refute has_element?(view, "#competence-reminder")
      assert has_element?(view, "#sequence-competence input[value='Résoudre une équation']")

      assert Assessment.sequence_competences(scope, [ctx.id], [seq.id]) ==
               %{{ctx.id, seq.id} => "Résoudre une équation"}
    end

    test "reminder can be dismissed and marks still save", %{
      conn: conn,
      ctx: ctx,
      seq: seq,
      a: a,
      s1: s1,
      scope: scope
    } do
      apc_on(scope)

      {:ok, view, _} =
        live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

      view |> element("#competence-reminder button") |> render_click()
      refute has_element?(view, "#competence-reminder")

      blur(view, s1.id, "12")
      assert [_] = Assessment.list_marks(scope, a)
    end

    test "APC off: no competence field", %{conn: conn, ctx: ctx, seq: seq} do
      {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")
      refute has_element?(view, "#sequence-competence")
      refute has_element?(view, "#competence-reminder")
    end
  end
end
