defmodule TeacherAssistantWeb.UIComponents do
  @moduledoc """
  Layout patterns shared by the screens (UI review 2026-10-14):

    * `save_bar/1` — one save for a whole form, shown only once something changed
      (the form carries `phx-hook="DirtyForm"`);
    * `settings_section/1` + `settings_row/1` — a settings card whose rows put the
      label and help on the left and the control, aligned, on the right;
    * `list_row/1` — the phone-friendly row that replaces table rows: leading
      visual, title, one line of meta, trailing value, chevron;
    * `action_menu/1` — secondary and destructive actions behind a « ⋯ » button
      instead of a row of text buttons.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import TeacherAssistantWeb.CoreComponents, only: [icon: 1]

  @doc """
  The bar at the bottom of a `DirtyForm` form: « Modifications non enregistrées ·
  Annuler · Enregistrer ». Hidden until a field differs from the saved values;
  sticky at the bottom of the viewport while visible. Place it last inside the form.
  """
  attr :label, :string, default: nil, doc: "the save button's label"
  attr :disabled, :boolean, default: false

  def save_bar(assigns) do
    ~H"""
    <div class="ta-savebar" role="region" aria-label={gettext("Modifications non enregistrées")}>
      <span class="ta-savebar__dot" aria-hidden="true"></span>
      <span class="min-w-0 flex-1 text-sm font-medium">
        {gettext("Modifications non enregistrées")}
      </span>
      <button type="reset" class="btn btn-ghost">{gettext("Annuler")}</button>
      <button
        type="submit"
        class="btn btn-primary"
        disabled={@disabled}
        phx-disable-with={gettext("Enregistrement…")}
      >
        {@label || gettext("Enregistrer")}
      </button>
    </div>
    """
  end

  @doc """
  A sub-page header: a back link to the parent page (« ‹ Paramètres »), the title,
  an optional subtitle and actions on the right.
  """
  attr :back, :string, required: true, doc: "the parent page's path"
  attr :back_label, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def back_header(assigns) do
    ~H"""
    <header class="flex flex-wrap items-end justify-between gap-3">
      <div class="min-w-0 space-y-1">
        <.link
          navigate={@back}
          class="inline-flex min-h-8 items-center gap-1 text-sm font-semibold text-info hover:underline"
        >
          <.icon name="hero-chevron-left" class="size-4" />{@back_label}
        </.link>
        <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">{@title}</h1>
        <p :if={@subtitle} class="text-[0.95rem] text-base-content/75">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc "A settings card: a title, an optional line of help, then `settings_row`s."
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil
  slot :actions
  slot :inner_block, required: true

  def settings_section(assigns) do
    ~H"""
    <section id={@id} class={["ta-section", @class]}>
      <header class="flex flex-wrap items-start justify-between gap-3 px-4 pb-2 pt-4 sm:px-5">
        <div class="min-w-0">
          <h2 class="text-base font-semibold">{@title}</h2>
          <p :if={@subtitle} class="mt-0.5 text-sm text-base-content/70">{@subtitle}</p>
        </div>
        <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  One setting: label and help on the left, the control on the right (stacked on
  phones). The control is the inner block, so pass a bare field (`label={nil}`).
  """
  attr :label, :string, required: true
  attr :for, :string, default: nil, doc: "the control's id, so the label focuses it"
  attr :help, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def settings_row(assigns) do
    ~H"""
    <div class={["ta-setting", @class]}>
      <div class="min-w-0">
        <label :if={@for} for={@for} class="text-[0.95rem] font-medium">{@label}</label>
        <span :if={!@for} class="text-[0.95rem] font-medium">{@label}</span>
        <p :if={@help} class="mt-0.5 text-sm text-base-content/70">{@help}</p>
      </div>
      <div class="ta-setting__control">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  A short number field with its unit inside (« 50 min », « 0,5 pt ») for a
  `settings_row`: full width on phones, a fixed width aligned right above.
  A text field with `inputmode` so French decimals (« 0,5 ») are accepted.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :unit, :string, required: true
  attr :placeholder, :string, default: nil
  attr :inputmode, :string, default: "decimal"

  def unit_input(assigns) do
    ~H"""
    <label class="input w-full sm:ml-auto sm:w-40">
      <input
        type="text"
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        inputmode={@inputmode}
        class="ta-num grow text-right"
      />
      <span class="text-sm text-base-content/70">{@unit}</span>
    </label>
    """
  end

  @doc """
  An on/off setting as a whole tappable row: label and help left, toggle right.
  Sends "false" when off (hidden field), "true" when on.
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :help, :string, default: nil
  attr :checked, :boolean, default: false
  attr :value, :string, default: "true"
  attr :hidden_false, :boolean, default: true

  def toggle_row(assigns) do
    ~H"""
    <label class="ta-setting cursor-pointer !grid-cols-[minmax(0,1fr)_auto] items-center">
      <span class="min-w-0">
        <span class="text-[0.95rem] font-medium">{@label}</span>
        <span :if={@help} class="mt-0.5 block text-sm text-base-content/70">{@help}</span>
      </span>
      <span class="ta-setting__control flex justify-end">
        <input :if={@hidden_false} type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          class="toggle toggle-primary"
          name={@name}
          value={@value}
          checked={@checked}
        />
      </span>
    </label>
    """
  end

  @doc """
  A tappable row (min 56px): `leading` (avatar, badge), the title and one meta
  line, an optional `trailing` value, then a chevron when it navigates.
  Give it `navigate`/`patch` to link, or `phx-click` (it is then a button).
  """
  attr :id, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :title, :string, required: true
  attr :meta, :string, default: nil
  attr :meta_class, :any, default: nil
  attr :selected, :boolean, default: false
  attr :rest, :global
  slot :leading
  slot :trailing
  slot :inner_block, doc: "extra content under the meta line"

  def list_row(assigns) do
    assigns = assign(assigns, :link?, !!(assigns.navigate || assigns.patch))

    ~H"""
    <.link
      :if={@link?}
      id={@id}
      navigate={@navigate}
      patch={@patch}
      class={["ta-list-row", @selected && "ta-list-row--selected"]}
      aria-current={@selected && "true"}
      {@rest}
    >
      <.list_row_body {assigns} />
      <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70" />
    </.link>
    <button
      :if={!@link? && @rest[:"phx-click"]}
      type="button"
      id={@id}
      class={["ta-list-row w-full text-left", @selected && "ta-list-row--selected"]}
      aria-current={@selected && "true"}
      {@rest}
    >
      <.list_row_body {assigns} />
      <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70" />
    </button>
    <div
      :if={!@link? && !@rest[:"phx-click"]}
      id={@id}
      class={["ta-list-row", @selected && "ta-list-row--selected"]}
      {@rest}
    >
      <.list_row_body {assigns} />
    </div>
    """
  end

  defp list_row_body(assigns) do
    ~H"""
    <span :if={@leading != []} class="shrink-0">{render_slot(@leading)}</span>
    <span class="flex min-w-0 flex-1 flex-col">
      <span class="truncate text-[0.95rem] font-medium">{@title}</span>
      <span :if={@meta} class={["truncate text-sm text-base-content/70", @meta_class]}>{@meta}</span>
      {render_slot(@inner_block)}
    </span>
    <span :if={@trailing != []} class="shrink-0 text-right">{render_slot(@trailing)}</span>
    """
  end

  @doc """
  « ⋯ » menu for a row's or a page's secondary actions. Each `item` is a link
  (`navigate`/`href`) or a button running `click` (an event name or a `JS`
  command, e.g. `JS.push("transfer", value: %{id: id})`), with an optional
  `confirm` question; `danger` items come last, in coral.
  """
  attr :id, :string, required: true
  attr :label, :string, default: nil, doc: "accessible name of the « ⋯ » button"
  attr :class, :any, default: nil

  slot :item, required: true do
    attr :navigate, :string
    attr :href, :string
    attr :target, :string
    attr :click, :any
    attr :confirm, :string
    attr :danger, :boolean
    attr :icon, :string
    attr :id, :string
  end

  def action_menu(assigns) do
    ~H"""
    <div id={@id} class={["dropdown dropdown-end", @class]}>
      <%!-- a focusable div, not a <button>: Safari does not focus a clicked button,
           and daisyUI's dropdown opens on focus --%>
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-square"
        aria-label={@label || gettext("Plus d'actions")}
        aria-haspopup="menu"
      >
        <.icon name="hero-ellipsis-horizontal" class="size-5" />
      </div>
      <ul
        tabindex="-1"
        role="menu"
        class="dropdown-content menu z-30 mt-1 w-60 rounded-box border border-base-300 bg-base-100 p-1.5 shadow-xl"
      >
        <li :for={item <- @item} role="none">
          <.link
            :if={item[:navigate] || item[:href]}
            role="menuitem"
            navigate={item[:navigate]}
            href={item[:href]}
            target={item[:target]}
            class={["min-h-11", item[:danger] && "text-error"]}
          >
            <.icon :if={item[:icon]} name={item.icon} class="size-4" />
            {render_slot(item)}
          </.link>
          <button
            :if={!(item[:navigate] || item[:href])}
            id={item[:id]}
            type="button"
            role="menuitem"
            class={["min-h-11", item[:danger] && "text-error"]}
            phx-click={item[:click]}
            data-confirm={item[:confirm]}
          >
            <.icon :if={item[:icon]} name={item.icon} class="size-4" />
            {render_slot(item)}
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
