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

  test "mention_badge shows word + a check for passing, x for failing, dash for nil" do
    assert render_component(&mention_badge/1, %{mention: :bien}) =~ "Bien"
    assert render_component(&mention_badge/1, %{mention: :bien}) =~ "hero-check-circle"
    assert render_component(&mention_badge/1, %{mention: nil}) =~ "Insuffisant"
    assert render_component(&mention_badge/1, %{mention: nil}) =~ "hero-x-circle"
  end
end
