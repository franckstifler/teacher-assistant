defmodule TeacherAssistantWeb.Modal do
  @moduledoc """
  A centred dialog over the page, rendered by the server like `Drawer`: the
  page shows it with `:if` and closes it by handling `on_close`. It is a real
  modal for assistive tech (`role="dialog"`, `aria-modal`, named by its
  title), focus moves into it and stays there, and Escape and the backdrop
  close it — unless `on_close` is nil, for a dialog that must be acknowledged
  with one of its own buttons.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :on_close, :any, default: nil, doc: "event or JS run on Escape and the backdrop"
  attr :class, :any, default: nil, doc: "extra classes for the box (width)"
  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="modal modal-open"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <.focus_wrap
        id={"#{@id}-box"}
        class={["modal-box space-y-4", @class]}
        phx-mounted={JS.focus_first()}
        phx-window-keydown={@on_close}
        phx-key={@on_close && "escape"}
      >
        <div>
          <p :if={@eyebrow} class="ta-eyebrow">{@eyebrow}</p>
          <h2 id={"#{@id}-title"} class={["text-lg font-semibold", @eyebrow && "mt-1"]}>
            {@title}
          </h2>
        </div>
        {render_slot(@inner_block)}
        <div :if={@actions != []} class="modal-action">{render_slot(@actions)}</div>
      </.focus_wrap>
      <div class="modal-backdrop" aria-hidden="true" phx-click={@on_close}></div>
    </div>
    """
  end
end
