defmodule TeacherAssistantWeb.PrintComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]

  alias TeacherAssistantWeb.PrintComponents

  defp setup_html(paper) do
    assigns = %{paper: paper}
    rendered_to_string(~H"<PrintComponents.setup paper={@paper} />")
  end

  test "a print page is laid out at its paper's width, never the phone's" do
    for {paper, width} <- [a4: 794, a4_landscape: 1123, a3_landscape: 1587, a5: 559] do
      html = setup_html(paper)
      assert html =~ ~s(<meta name="viewport" content="width=#{width}">)
      refute html =~ "device-width,"
    end
  end

  test "on a phone the print bar is zoomed back to its normal size; on paper it is hidden" do
    html = setup_html(:a4)
    assert html =~ "(max-device-width: 640px) { .print-actions { zoom: 2.04; } }"
    assert html =~ "@media print { .print-actions { display: none; } }"
  end

  test "the print bar prints the page" do
    assigns = %{}
    html = rendered_to_string(~H"<PrintComponents.print_bar />")
    assert html =~ ~s(class="print-actions")
    assert html =~ ~s(onclick="window.print\(\)")
    assert html =~ "Imprimer"
  end

  # The pages people print declare their paper; the verify pages (opened on a
  # phone after scanning a QR code) stay at the phone's width.
  test "every standalone print page uses the shared setup" do
    templates = Path.wildcard("lib/teacher_assistant_web/controllers/*_print_html/*.html.heex")
    assert length(templates) >= 12

    for path <- templates do
      source = File.read!(path)
      assert source =~ "<TeacherAssistantWeb.PrintComponents.setup paper=", path
      refute source =~ "width=device-width", path
      assert source =~ "print-actions" or source =~ "PrintComponents.print_bar", path
    end
  end
end
