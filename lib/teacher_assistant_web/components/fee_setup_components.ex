defmodule TeacherAssistantWeb.FeeSetupComponents do
  @moduledoc """
  The three numbered steps of the fee setup (UX refonte 2026-11-03, SFees): fee types →
  amounts per level → tranches, each unlocking the next. Used by the fee settings page
  (with each step's controls inside) and by the Frais page before anything is set up.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import TeacherAssistantWeb.CoreComponents, only: [icon: 1]

  @doc """
  The step state from `Fees.setup_status/2`'s `done` (steps completed in order):
  `:done`, `:current` (the first not done) or `:locked` (after it).
  """
  def step_state(n, done) when n <= done, do: :done
  def step_state(n, done) when n == done + 1, do: :current
  def step_state(_n, _done), do: :locked

  attr :id, :string, required: true
  attr :n, :integer, required: true
  attr :state, :atom, required: true, values: [:done, :current, :locked]
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :summary, :string, default: nil, doc: "a short « what is set » line once done"
  attr :open, :boolean, default: true, doc: "show the inner block (controls)"
  slot :inner_block

  def fee_step(assigns) do
    ~H"""
    <li
      id={@id}
      data-state={@state}
      class={[
        "flex gap-3.5 rounded-box border bg-base-100 p-4 transition-colors sm:p-5",
        @state == :current && "border-2 border-primary",
        @state == :done && "border-base-300",
        @state == :locked && "border-base-300 opacity-70"
      ]}
    >
      <span
        aria-hidden="true"
        class={[
          "ta-num grid size-7 shrink-0 place-items-center rounded-full text-[0.8rem] font-semibold",
          @state == :current && "bg-primary text-primary-content",
          @state == :done && "bg-primary/15 text-primary",
          @state == :locked && "border border-base-300 text-base-content/70"
        ]}
      >
        <.icon :if={@state == :done} name="hero-check" class="size-4" />
        <span :if={@state != :done}>{@n}</span>
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-3">
        <div>
          <h2 class="flex flex-wrap items-baseline gap-x-2 text-base font-semibold">
            {@title}
            <span :if={@state == :locked} class="text-xs font-normal text-base-content/70">
              {gettext("après l'étape %{n}", n: @n - 1)}
            </span>
          </h2>
          <p :if={@description} class="mt-0.5 text-sm text-base-content/70">{@description}</p>
          <p :if={@summary} class="mt-0.5 text-sm font-medium text-primary">{@summary}</p>
        </div>
        <div :if={@open and @inner_block != []} class="min-w-0">{render_slot(@inner_block)}</div>
      </div>
    </li>
    """
  end
end
