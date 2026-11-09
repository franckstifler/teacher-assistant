defmodule TeacherAssistantWeb.PrintComponents do
  @moduledoc """
  Pieces shared by the standalone print pages (bulletins, cards, lists,
  timetables, receipts, fee papers…).

  Phones lay a page out at the screen's width and some of them print that
  layout as it is, squeezed onto the sheet. A print page therefore lays itself
  out at the width of its paper: the phone shows the whole sheet, zoomed out,
  and prints it as a computer would.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  # Width of each sheet in CSS pixels (96 per inch), matching the page's `@page`.
  @widths %{a4: 794, a4_landscape: 1123, a3_landscape: 1587, a5: 559}

  # A phone (about 390 px wide) shows the sheet zoomed out by 390 / width; the
  # print bar is zoomed back in by the inverse so its buttons stay tappable.
  @phone_width 390

  @doc """
  Goes in the `<head>`, before the page's own `<style>` (which may restyle the
  print bar): the viewport of a page printed on `paper`, and the print bar's
  base style — hidden on paper, back to its normal size on a phone.
  """
  attr :paper, :atom, required: true, values: Map.keys(@widths)

  def setup(assigns) do
    width = Map.fetch!(@widths, assigns.paper)
    assigns = assign(assigns, width: width, zoom: Float.round(width / @phone_width, 2))

    ~H"""
    <meta name="viewport" content={"width=#{@width}"} />
    <style>
      .print-actions { margin: 0 0 12px; }
      .print-actions button { font: 15px system-ui, sans-serif; padding: 9px 16px; cursor: pointer; }
      @media screen and (max-device-width: 640px) { .print-actions { zoom: <%= @zoom %>; } }
      @media print { .print-actions { display: none; } }
    </style>
    """
  end

  @doc "The bar holding the « Imprimer » button, for pages that have nothing else in it."
  def print_bar(assigns) do
    ~H"""
    <div class="print-actions">
      <button type="button" onclick="window.print()">{gettext("Imprimer")}</button>
    </div>
    """
  end
end
