defmodule TeacherAssistantWeb.Drawer do
  @moduledoc """
  A side panel over the page (spec 2026-10-08), rendered by the server: the page
  shows it with `:if` and closes it by handling `on_close`. Focus stays inside
  while it is open; Escape and the backdrop close it.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias Phoenix.LiveView.JS
  import TeacherAssistantWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :on_close, JS, default: %JS{}, doc: "run on Escape, the backdrop and the close button"
  slot :inner_block, required: true
  slot :footer

  def drawer(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-40"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
    >
      <div
        class="absolute inset-0 bg-black/50"
        aria-hidden="true"
        phx-mounted={JS.transition({"ease-out duration-200", "opacity-0", "opacity-100"})}
        phx-click={@on_close}
      >
      </div>
      <.focus_wrap
        id={"#{@id}-panel"}
        phx-mounted={
          JS.transition({"ease-out duration-200", "translate-x-full", "translate-x-0"})
          |> JS.focus_first()
        }
        phx-key="escape"
        phx-window-keydown={@on_close}
        class="absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l border-base-300 bg-base-100 shadow-2xl"
      >
        <header class="flex items-start justify-between gap-3 border-b border-base-300 px-5 py-4">
          <div>
            <p :if={@eyebrow} class="ta-eyebrow">{@eyebrow}</p>
            <h2 id={"#{@id}-title"} class="mt-1 text-xl font-semibold">{@title}</h2>
          </div>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-square"
            aria-label={gettext("Fermer")}
            phx-click={@on_close}
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        <div class="flex-1 space-y-5 overflow-y-auto px-5 py-5">
          {render_slot(@inner_block)}
        </div>
        <footer
          :if={@footer != []}
          class="flex flex-wrap justify-end gap-2 border-t border-base-300 px-5 py-4"
        >
          {render_slot(@footer)}
        </footer>
      </.focus_wrap>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, default: false
  attr :id, :string, required: true
  slot :inner_block, required: true

  @doc "A chip-styled radio (sous-système, niveau, série, sexe…)."
  def chip_radio(assigns) do
    ~H"""
    <label
      for={@id}
      class={[
        "cursor-pointer select-none rounded-full border px-3 py-1.5 text-sm font-semibold transition-colors",
        "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-primary",
        if(@checked,
          do: "border-primary bg-primary/15 text-primary",
          else: "border-base-300 text-base-content/80 hover:border-base-content/40"
        )
      ]}
    >
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="sr-only"
      />
      {render_slot(@inner_block)}
    </label>
    """
  end
end
