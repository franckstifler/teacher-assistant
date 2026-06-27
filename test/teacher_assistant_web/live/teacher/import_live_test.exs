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
    assert render(view) =~ "truncated to 300"
  end
end
