defmodule TeacherAssistantWeb.Teacher.ImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  defp seed_year_and_context(ws) do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{year: year, ctx: ctx}
  end

  test "shows the upload form when a teaching context exists", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-upload-form")
    assert has_element?(view, "#import-context-select")
  end

  test "gates to setup when there is no teaching context", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-context-gate")
    refute has_element?(view, "#import-upload-form")
  end

  test "shows the three-step stepper on the upload stage", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    assert has_element?(view, "#import-stepper")
    html = render(element(view, "#import-stepper"))
    assert html =~ "Téléversement"
    assert html =~ "Vérification"
    # third step label is localized ("Save" / "Enregistrer") — assert the step exists
    assert length(String.split(html, "<li")) == 4
  end

  test "extracts and renders a review table from the uploaded PDF", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)

    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, """
    Module             Lecon                Duree
    Algebre            Les entiers          2
    Algebre            Evaluation           1
    """)

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    pdf = %{name: "fiche.pdf", content: "%PDF-1.4 stub", type: "application/pdf"}
    input = file_input(view, "#import-upload-form", :fiche, [pdf])
    render_upload(input, "fiche.pdf")

    view
    |> element("#import-upload-form")
    |> render_submit(%{"context_id" => "", "title" => "Imported"})

    assert has_element?(view, "#import-review")
    assert has_element?(view, "#import-rows")
    assert render(view) =~ "Les entiers"
    assert render(view) =~ "Evaluation"
  end

  test "caps parsed rows at 300 and shows truncation notice", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)

    header = "Module             Lecon                Duree\n"

    data_lines =
      Enum.map_join(1..350, "\n", fn i ->
        String.pad_trailing("Algebre", 19) <>
          String.pad_trailing("Lecon #{i}", 21) <>
          "1"
      end)

    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, header <> data_lines)

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    pdf = %{name: "fiche.pdf", content: "%PDF-1.4 stub", type: "application/pdf"}
    input = file_input(view, "#import-upload-form", :fiche, [pdf])
    render_upload(input, "fiche.pdf")

    view
    |> element("#import-upload-form")
    |> render_submit(%{"context_id" => "", "title" => "Imported"})

    assert has_element?(view, "#import-row-299")
    refute has_element?(view, "#import-row-300")
    assert has_element?(view, "#import-truncation-notice")
  end

  test "saving the reviewed rows creates a draft plan and navigates to it", %{
    conn: conn,
    workspace: ws
  } do
    %{ctx: ctx} = seed_year_and_context(ws)
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)

    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, """
    Module    Lecon          Duree
    Algebre   Les entiers    2
    """)

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    input =
      file_input(view, "#import-upload-form", :fiche, [
        %{name: "f.pdf", content: "x", type: "application/pdf"}
      ])

    render_upload(input, "f.pdf")

    view
    |> element("#import-upload-form")
    |> render_submit(%{"context_id" => ctx.id, "title" => "Imported plan"})

    view
    |> form("#import-review-form", %{
      "title" => "Imported plan",
      "rows" => %{
        "0" => %{
          "module" => "Algebre",
          "lesson_title" => "Les entiers",
          "planned_hours" => "2",
          "entry_type" => "lesson",
          "week_no" => "",
          "sequence_id" => ""
        }
      }
    })
    |> render_submit()

    [plan] = Academics.list_progression_plans(ws)
    assert plan.title == "Imported plan"
    assert plan.status == :draft
    assert [entry] = Academics.list_progression_entries(plan)
    assert entry.lesson_title == "Les entiers"
  end

  test "cannot import into another teacher's context", %{workspace: ws} do
    seed_year_and_context(ws)

    other_ws =
      Academics.ensure_personal_workspace!(TeacherAssistant.TeacherFixtures.user_fixture())

    {:ok, other_year} =
      Academics.create_academic_year(other_ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, other_ctx} =
      Academics.create_teaching_context(other_ws, other_year, %{
        subject: "Physics",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 3
      })

    assert {:error, :not_found} =
             Academics.import_progression_plan(
               ws,
               %{teaching_context_id: other_ctx.id, title: "Nope"},
               [
                 %{
                   module: "M",
                   lesson_title: "L",
                   planned_hours: Decimal.new("1"),
                   entry_type: :lesson
                 }
               ]
             )
  end
end
