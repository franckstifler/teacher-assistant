defmodule TeacherAssistantWeb.Teacher.MarksRefonteTest do
  @moduledoc "The marks page of the UX refonte (spec 2026-11-03, Batch 1)."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.MarksFixtures

  setup %{conn: conn} do
    world = MarksFixtures.marks_world()

    conn =
      conn
      |> log_in_user(world.t.current_user)
      |> Plug.Conn.put_session(:workspace_id, world.head.current_workspace.id)

    path = ~p"/teacher/contexts/#{world.tc.id}/marks?seq=#{world.seq.id}&assessment=#{world.a.id}"
    Map.merge(world, %{conn: conn, path: path})
  end

  defp blur(view, student_id, value),
    do: view |> element("#mark-input-#{student_id}") |> render_blur(%{"value" => value})

  describe "phone list" do
    test "a task header back to Mes cours, the course and the séquence pickers", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      assert has_element?(view, "#marks-back[href='/school/courses']")
      assert has_element?(view, "#course-picker-open", "2 élèves")
      assert has_element?(view, "#seq-picker-open", "Séq. #{ctx.seq.number}")
      # the Résultats / Élèves tabs stay
      assert has_element?(view, "#teaching-nav-summary")
      assert has_element?(view, "#teaching-nav-roster")
    end

    test "evaluation chips count their own marks and tick once complete", ctx do
      {:ok, b} = Assessment.create_assessment(ctx.t, ctx.tc, ctx.seq, %{label: "Devoir 2"})

      :ok =
        Assessment.upsert_marks(ctx.t, b, [
          %{student_id: ctx.s1.id, score: Decimal.new(12)},
          %{student_id: ctx.s2.id, status: :absent}
        ])

      {:ok, view, _} = live(ctx.conn, ctx.path)

      assert has_element?(view, "#eval-chip-#{ctx.a.id}[aria-current='page']", "0/2")
      assert has_element?(view, "#eval-chip-#{b.id}", "2/2")
      assert has_element?(view, "#eval-chip-#{b.id} .hero-check")
      assert has_element?(view, "#eval-card-#{b.id}", "2/2")

      # the selected one follows what is typed
      blur(view, ctx.s1.id, "15")
      assert has_element?(view, "#eval-chip-#{ctx.a.id}", "1/2")
    end

    test "the next empty box is marked, then moves on", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      assert has_element?(view, "#mark-row-#{ctx.s1.id}[data-next='true']")
      blur(view, ctx.s1.id, "12")
      refute has_element?(view, "#mark-row-#{ctx.s1.id}[data-next]")
      assert has_element?(view, "#mark-row-#{ctx.s2.id}[data-next='true']")
      assert has_element?(view, "#goto-next-empty")
    end

    test "the bottom bar counts, shows the average in red under 10 and opens the keypad", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      assert has_element?(view, "#keypad-open", "Saisir les 2 notes manquantes")
      blur(view, ctx.s1.id, "6")

      assert has_element?(view, "#bottom-progress", "1")
      assert has_element?(view, "#bottom-average .text-error", "6")
      assert has_element?(view, "#marks-average-preview .text-error", "6")
      assert has_element?(view, "#keypad-open", "Saisir la note manquante")

      blur(view, ctx.s2.id, "18")
      assert has_element?(view, "#bottom-average .text-primary", "12")
      refute has_element?(view, "#keypad-open")
    end

    test "the competence is one line on phones, its form in a sheet", ctx do
      {:ok, _} =
        Assessment.update_bulletin_settings(ctx.head, %{
          "language" => "by_class",
          "elements" => ["apc"]
        })

      {:ok, view, _} = live(ctx.conn, ctx.path)
      assert has_element?(view, "#competence-open", "à renseigner")

      view |> element("#competence-open") |> render_click()

      view
      |> form("#sequence-competence-sheet", %{competence: %{text: "Lire un texte"}})
      |> render_submit()

      refute has_element?(view, "#competence-sheet")
      assert has_element?(view, "#competence-open", "Lire un texte")
    end
  end

  describe "keypad" do
    test "opens on the first empty student; Suivant saves and moves on", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      view |> element("#keypad-open") |> render_click()
      assert has_element?(view, "#marks-keypad[data-student='#{ctx.s1.id}']")
      assert has_element?(view, "#keypad-student", "Awa")
      assert has_element?(view, "#keypad-remaining", "2 restants")
      # the count has its own element (it never truncates); the next students fill the space
      assert has_element?(view, "#keypad-progress", "0/2 saisies")
      assert has_element?(view, "#keypad-next", "Beti")
      refute has_element?(view, "#keypad-prev div")

      render_hook(view, "keypad_next", %{"student" => ctx.s1.id, "value" => "13,5"})

      assert [m] = Assessment.list_marks(ctx.t, ctx.a)
      assert Decimal.equal?(m.score, Decimal.new("13.5"))
      assert has_element?(view, "#marks-keypad[data-student='#{ctx.s2.id}']")
      assert has_element?(view, "#keypad-remaining", "1 restant")

      # ABS on the last student saves the absence and goes back to the list
      render_hook(view, "keypad_next", %{"student" => ctx.s2.id, "value" => "abs"})
      refute has_element?(view, "#marks-keypad")
      assert has_element?(view, "#mark-input-#{ctx.s2.id}[value='abs']")
    end

    test "a refused value keeps the student in focus with its error", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)
      render_hook(view, "keypad_open", %{"student" => ctx.s1.id})

      render_hook(view, "keypad_next", %{"student" => ctx.s1.id, "value" => "25"})

      assert has_element?(view, "#marks-keypad[data-student='#{ctx.s1.id}']")
      assert has_element?(view, "#keypad-error", "Note entre 0 et 20")
      assert Assessment.list_marks(ctx.t, ctx.a) == []
    end

    test "↑ goes back, ✕ saves and closes", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)
      render_hook(view, "keypad_open", %{"student" => ctx.s2.id})

      render_hook(view, "keypad_prev", %{"student" => ctx.s2.id, "value" => ""})
      assert has_element?(view, "#marks-keypad[data-student='#{ctx.s1.id}']")

      render_hook(view, "keypad_close", %{"student" => ctx.s1.id, "value" => "9"})
      refute has_element?(view, "#marks-keypad")
      assert [%{student_id: sid}] = Assessment.list_marks(ctx.t, ctx.a)
      assert sid == ctx.s1.id
    end

    test "a locked séquence never opens it", ctx do
      MarksFixtures.lock!(ctx, Date.add(TeacherAssistant.Academics.Reference.today(), -1))
      {:ok, view, _} = live(ctx.conn, ctx.path)

      render_hook(view, "keypad_open", %{"student" => ctx.s1.id})
      refute has_element?(view, "#marks-keypad")
    end
  end

  describe "new evaluation sheet" do
    test "picking a type fills the name; creating starts the entry in the keypad", ctx do
      [type | _] = Assessment.list_assessment_types(ctx.head)
      {:ok, view, _} = live(ctx.conn, ctx.path)

      view |> element("#new-eval-chip") |> render_click()
      assert has_element?(view, "#new-eval-type-#{type.id}")

      view
      |> form("#new-assessment-form")
      |> render_change(%{
        "_target" => ["assessment", "assessment_type_id"],
        "assessment" => %{"assessment_type_id" => type.id, "label" => ""}
      })

      assert has_element?(view, "#new-assessment-form input[value='#{type.name} 1']")

      # a name the teacher wrote is kept
      view
      |> form("#new-assessment-form")
      |> render_change(%{
        "_target" => ["assessment", "assessment_type_id"],
        "assessment" => %{"assessment_type_id" => type.id, "label" => "Mon devoir"}
      })

      assert has_element?(view, "#new-assessment-form input[value='Mon devoir']")

      view
      |> form("#new-assessment-form", %{
        "assessment" => %{"assessment_type_id" => type.id, "label" => "Mon devoir"}
      })
      |> render_submit()

      created =
        Enum.find(
          Assessment.list_assessments(ctx.t, ctx.tc, ctx.seq),
          &(&1.label == "Mon devoir")
        )

      assert created.assessment_type_id == type.id
      assert has_element?(view, "#eval-card-#{created.id}[aria-current='page']")
      assert has_element?(view, "#marks-keypad[data-student='#{ctx.s1.id}']")
      refute has_element?(view, "#new-eval-sheet")
    end
  end

  describe "evaluation menu" do
    test "renames and changes the maximum", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      view |> element("#eval-edit") |> render_click()

      view
      |> form("#edit-assessment-form", %{edit: %{label: "Devoir A", max_score: "10"}})
      |> render_submit()

      {:ok, a} = Assessment.fetch_owned_assessment(ctx.t, ctx.a.id)
      assert a.label == "Devoir A"
      assert Decimal.equal?(a.max_score, 10)
      assert has_element?(view, "#eval-card-#{a.id}", "/10")
      refute has_element?(view, "#edit-eval-sheet")
    end

    test "refuses a maximum under an entered mark, or a name already taken", ctx do
      {:ok, _} = Assessment.create_assessment(ctx.t, ctx.tc, ctx.seq, %{label: "Devoir 2"})
      {:ok, view, _} = live(ctx.conn, ctx.path)
      blur(view, ctx.s1.id, "15")

      view |> element("#eval-edit") |> render_click()

      html =
        view
        |> form("#edit-assessment-form", %{edit: %{label: "Devoir 1", max_score: "10"}})
        |> render_submit()

      assert html =~ "dépassent ce barème"

      html =
        view
        |> form("#edit-assessment-form", %{edit: %{label: "Devoir 2", max_score: "20"}})
        |> render_submit()

      assert html =~ "porte déjà ce nom"
      {:ok, a} = Assessment.fetch_owned_assessment(ctx.t, ctx.a.id)
      assert {a.label, Decimal.to_integer(a.max_score)} == {"Devoir 1", 20}
    end
  end

  describe "side panel" do
    test "names the boxes to correct, then says everything is saved", ctx do
      {:ok, view, _} = live(ctx.conn, ctx.path)

      blur(view, ctx.s1.id, "25")
      assert has_element?(view, "#marks-to-fix", "1 note à corriger (Awa)")
      assert has_element?(view, "#mark-row-#{ctx.s1.id} .text-error .hero-exclamation-circle")

      blur(view, ctx.s1.id, "12")
      refute has_element?(view, "#marks-to-fix")
      assert has_element?(view, "#marks-saved-line", "Tout est enregistré")
      assert has_element?(view, "#mark-row-#{ctx.s1.id} .hero-check")
    end
  end
end
