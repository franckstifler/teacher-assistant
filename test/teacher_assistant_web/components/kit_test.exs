defmodule TeacherAssistantWeb.KitTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistantWeb.CoreComponents

  test "page_header renders eyebrow, title, and actions" do
    html =
      render_component(&page_header/1, %{
        eyebrow: "Séquence 2",
        title: "Maths · 3e M2",
        actions: [%{inner_block: fn _, _ -> "ACT" end}]
      })

    assert html =~ "Séquence 2"
    assert html =~ "Maths · 3e M2"
    assert html =~ "ACT"
  end

  test "stat renders label, value, suffix" do
    html = render_component(&stat/1, %{label: "Moyenne", value: "12,4", suffix: "/20"})
    assert html =~ "Moyenne"
    assert html =~ "12,4"
    assert html =~ "/20"
    assert html =~ "ta-num"
  end

  test "empty_state renders icon title and action" do
    html =
      render_component(&empty_state/1, %{
        icon: "hero-inbox",
        title: "Nothing yet",
        action: [%{inner_block: fn _, _ -> "GO" end}]
      })

    assert html =~ "Nothing yet"
    assert html =~ "GO"
  end

  test "setup_gate renders message and action" do
    html =
      render_component(&setup_gate/1, %{
        icon: "hero-academic-cap",
        eyebrow: "Get started",
        title: "Welcome",
        message: "Set up your year",
        action: [%{inner_block: fn _, _ -> "START" end}]
      })

    assert html =~ "Welcome"
    assert html =~ "Set up your year"
    assert html =~ "START"
  end

  test "mention_badge shows the appreciation with a check when passed, an x otherwise" do
    passed = render_component(&mention_badge/1, %{mention: %{label: "Bien", passed?: true}})
    assert passed =~ "Bien"
    assert passed =~ "hero-check-circle"

    failed = render_component(&mention_badge/1, %{mention: %{label: "Médiocre", passed?: false}})
    assert failed =~ "Médiocre"
    assert failed =~ "hero-x-circle"

    assert render_component(&mention_badge/1, %{mention: nil}) =~ "—"
  end

  test "distinction_badge names the distinction" do
    assert render_component(&distinction_badge/1, %{distinction: :tableau_honneur}) =~
             "Tableau d&#39;honneur"

    assert render_component(&distinction_badge/1, %{distinction: :blame_travail}) =~
             "Blâme travail"
  end
end
