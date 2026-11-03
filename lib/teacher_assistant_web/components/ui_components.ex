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

  And the pieces of the UX refonte (spec 2026-11-03, « Shared pieces »):
  `filter_pills/1`, `class_picker/1`, `level_group/1`, `progress_meter/1`,
  `bulk_bar/1`, `attention_card/1` + `attention_row/1`, `stat_tile/1`, and
  `back_header/1`'s `task` mode (the phone task header).
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import TeacherAssistantWeb.CoreComponents, only: [breadcrumb: 1, icon: 1]

  alias TeacherAssistant.Academics.SchoolTemplates

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
  A sub-page header: the breadcrumb « Paramètres / title » back to the parent page,
  the title, an optional subtitle and actions on the right. A page that is itself
  in the member's menu (the intendant's fee settings) passes `back={nil}`: no crumb.

  With `task`, it is also the phone task header: below `sm` a back arrow replaces
  the breadcrumb and the title, subtitle and actions share one compact row (pair
  it with `<Layouts.app immersive>`); from `sm` it is the header above.

      <.back_header task back={~p"/school/courses"} title="Maths · 6ème" subtitle="2 classes">
        <:actions><button class="btn btn-sm">Séq. 2</button></:actions>
      </.back_header>
  """
  attr :back, :string, default: nil, doc: "the parent page's path"
  attr :back_label, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :task, :boolean, default: false, doc: "a compact back-arrow header on phones"
  slot :actions

  def back_header(assigns) do
    ~H"""
    <header class={[
      "flex gap-3",
      if(@task,
        do: "items-center gap-2 sm:flex-wrap sm:items-end sm:justify-between sm:gap-3",
        else: "flex-wrap items-end justify-between"
      )
    ]}>
      <.link
        :if={@task && @back}
        id="back-header-arrow"
        navigate={@back}
        aria-label={@back_label || gettext("Retour")}
        class="btn btn-ghost btn-square -ml-2 shrink-0 sm:hidden"
      >
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <div class={["min-w-0 space-y-1", @task && "flex-1 space-y-0 sm:flex-none sm:space-y-1"]}>
        <div :if={@back} class={@task && "hidden sm:block"}>
          <.breadcrumb>
            <:crumb id="back-header-parent" navigate={@back}>{@back_label}</:crumb>
            <:crumb>{@title}</:crumb>
          </.breadcrumb>
        </div>
        <h1 class={[
          "font-semibold leading-tight sm:text-[2rem]",
          if(@task, do: "truncate text-lg sm:whitespace-normal", else: "text-2xl")
        ]}>
          {@title}
        </h1>
        <p
          :if={@subtitle}
          class={[
            "text-base-content/75",
            if(@task, do: "truncate text-sm sm:text-[0.95rem]", else: "text-[0.95rem]")
          ]}
        >
          {@subtitle}
        </p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
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

  attr :trigger_label, :string,
    default: nil,
    doc: "text shown before the « ⋯ » (« Évaluation 2 ⋯ »): a labelled button, not a square"

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
        class={[
          "btn",
          if(@trigger_label,
            do: "btn-outline btn-sm gap-1.5 border-base-300 font-medium text-base-content/80",
            else: "btn-ghost btn-square"
          )
        ]}
        aria-label={@label || gettext("Plus d'actions")}
        aria-haspopup="menu"
      >
        <span :if={@trigger_label} class="max-w-40 truncate">{@trigger_label}</span>
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
            id={item[:id]}
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

  @doc ~S"""
  A row of filter pills: patch links, each with its count (« Toutes 41 », « Sans
  PP 3 »); the current one carries `aria-current`. One row scrolling sideways on
  phones, wrapping from `sm`.

      <.filter_pills id="class-filters">
        <:pill :for={f <- @filters} patch={~p"/school/classes?f=#{f}"} count={@counts[f]}
          current={f == @filter}>{label(f)}</:pill>
      </.filter_pills>
  """
  attr :id, :string, required: true
  attr :label, :string, default: nil, doc: "accessible name of the row (default « Filtres »)"
  attr :class, :any, default: nil

  slot :pill, required: true do
    attr :patch, :string, required: true
    attr :count, :integer, doc: "shown after the label when given (0 included)"
    attr :current, :boolean
    attr :id, :string
  end

  def filter_pills(assigns) do
    ~H"""
    <nav id={@id} aria-label={@label || gettext("Filtres")} class={["ta-pills", @class]}>
      <.link
        :for={pill <- @pill}
        id={pill[:id]}
        patch={pill.patch}
        class="ta-pill"
        aria-current={pill[:current] && "true"}
      >
        {render_slot(pill)}
        <span :if={pill[:count]} class="ta-pill__count ta-num">{pill.count}</span>
      </.link>
    </nav>
    """
  end

  @doc ~S"""
  Picks a class: a native select with one `optgroup` per level (classes in
  `SchoolTemplates.class_sort_key/1` order) between ‹ › buttons that patch to the
  previous and next class. `suffix` adds a short text to each option
  (« 6ème A · 7 élèves »).

  With `change`, the picker is its own form sending that event (the select is
  named `name`); without it, place it inside the page's own `phx-change` form.

      <.class_picker id="conduct-class" classes={@classes} current={@cg && @cg.id}
        to={fn c -> ~p"/school/conduct?class=#{c.id}" end} change="pick"
        suffix={fn c -> ngettext("%{count} élève", "%{count} élèves", c.enrollment_count) end} />
  """
  attr :id, :string, required: true
  attr :classes, :list, required: true, doc: "the classes (`id`, `label`, `level`), any order"
  attr :current, :string, default: nil, doc: "the selected class's id"
  attr :to, :any, default: nil, doc: "`fn class -> path end`: where ‹ › patch to (with `stepper`)"
  attr :suffix, :any, default: nil, doc: "`fn class -> text | nil end`, after « · »"
  attr :name, :string, default: "class"
  attr :change, :string, default: nil, doc: "the `phx-change` event of its own form"
  attr :prompt, :string, default: nil, doc: "a first, empty option (« Toutes les classes »)"
  attr :label, :string, default: nil, doc: "the select's accessible name (default « Classe »)"
  attr :stepper, :boolean, default: true, doc: "false: the select alone, without ‹ ›"
  attr :select_class, :any, default: "select-sm", doc: "the select's size/extra classes"
  attr :class, :any, default: nil

  def class_picker(assigns) do
    sorted = Enum.sort_by(assigns.classes, &SchoolTemplates.class_sort_key/1)
    index = assigns.current && Enum.find_index(sorted, &(&1.id == assigns.current))

    assigns =
      assign(assigns,
        groups: Enum.chunk_by(sorted, & &1.level),
        prev: if(index && index > 0, do: Enum.at(sorted, index - 1)),
        next: if(index, do: Enum.at(sorted, index + 1))
      )

    ~H"""
    <div id={@id} class={["flex items-center gap-1", @class]}>
      <.class_step
        :if={@stepper}
        id={"#{@id}-prev"}
        target={@prev}
        to={@to}
        icon="hero-chevron-left"
        label={gettext("Classe précédente")}
      />
      <.dynamic_tag
        tag_name={if @change, do: "form", else: "div"}
        id={@change && "#{@id}-form"}
        phx-change={@change}
        class="min-w-0 flex-1"
      >
        <select
          id={"#{@id}-select"}
          name={@name}
          aria-label={@label || gettext("Classe")}
          class={["select w-full", @select_class]}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          <optgroup :for={[first | _] = group <- @groups} label={first.level || gettext("Autres")}>
            <option :for={c <- group} value={c.id} selected={c.id == @current}>
              {option_text(c, @suffix)}
            </option>
          </optgroup>
        </select>
      </.dynamic_tag>
      <.class_step
        :if={@stepper}
        id={"#{@id}-next"}
        target={@next}
        to={@to}
        icon="hero-chevron-right"
        label={gettext("Classe suivante")}
      />
    </div>
    """
  end

  defp class_step(assigns) do
    ~H"""
    <.link
      :if={@target}
      id={@id}
      patch={@to.(@target)}
      class="btn btn-ghost btn-square btn-sm shrink-0"
      aria-label={@label}
      title={@target.label}
    >
      <.icon name={@icon} class="size-4" />
    </.link>
    <span
      :if={!@target}
      class="btn btn-ghost btn-square btn-sm btn-disabled shrink-0"
      aria-hidden="true"
    >
      <.icon name={@icon} class="size-4" />
    </span>
    """
  end

  defp option_text(class, nil), do: class.label

  defp option_text(class, suffix) do
    case suffix.(class) do
      text when is_binary(text) and text != "" -> "#{class.label} · #{text}"
      _ -> class.label
    end
  end

  @doc """
  A level's section: the header « 6ème · 3 classes · 142 élèves », then its rows.

      <.level_group :for={{level, rows} <- @by_level} level={level} classes={length(rows)}
        students={Enum.sum_by(rows, & &1.enrollment_count)}>...</.level_group>
  """
  attr :id, :string, default: nil
  attr :level, :string, required: true, doc: "the level's label, as the app shows it"
  attr :classes, :integer, required: true, doc: "how many classes"
  attr :students, :integer, default: nil, doc: "how many students, when known"
  attr :class, :any, default: nil
  slot :actions
  slot :inner_block, required: true

  def level_group(assigns) do
    ~H"""
    <section id={@id} class={["space-y-2", @class]}>
      <header class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 px-1">
        <h2 class="min-w-0 text-[0.95rem] font-semibold">
          {@level}
          <span class="font-normal text-base-content/70">
            · {ngettext("%{count} classe", "%{count} classes", @classes)}<span :if={@students}> · {ngettext(
              "%{count} élève",
              "%{count} élèves",
              @students
            )}</span>
          </span>
        </h2>
        <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  « 18/42 » and a thin bar under it, with an optional label on the left. The tone
  follows completion unless given: nothing yet is neutral, partly done amber,
  done green.

      <.progress_meter label="Notes saisies" value={18} total={42} />
  """
  attr :id, :string, default: nil
  attr :value, :integer, required: true
  attr :total, :integer, required: true
  attr :label, :string, default: nil
  attr :tone, :atom, default: :auto, values: [:auto, :neutral, :warning, :error, :primary]
  attr :class, :any, default: nil

  def progress_meter(assigns) do
    %{value: value, total: total} = assigns
    pct = if total > 0, do: min(round(value * 100 / total), 100), else: 0
    assigns = assign(assigns, pct: pct, tone: meter_tone(assigns.tone, value, total))

    ~H"""
    <div id={@id} class={["flex min-w-0 flex-col gap-1", @class]}>
      <div class="flex items-baseline justify-between gap-2 text-xs">
        <span :if={@label} class="truncate text-base-content/75">{@label}</span>
        <span class={["ta-num ml-auto shrink-0", @tone == :primary && "text-primary"]}>
          {@value}/{@total}
        </span>
      </div>
      <div
        class="h-1.5 overflow-hidden rounded-full bg-base-300/70"
        role="progressbar"
        aria-label={@label || gettext("Progression")}
        aria-valuemin="0"
        aria-valuemax={@total}
        aria-valuenow={@value}
      >
        <div
          class={["h-full rounded-full transition-[width] duration-500", meter_bar(@tone)]}
          style={"width: #{@pct}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp meter_tone(:auto, _value, total) when total <= 0, do: :neutral
  defp meter_tone(:auto, value, total) when value >= total, do: :primary
  defp meter_tone(:auto, value, _total) when value <= 0, do: :neutral
  defp meter_tone(:auto, _value, _total), do: :warning
  defp meter_tone(tone, _value, _total), do: tone

  defp meter_bar(:primary), do: "bg-primary"
  defp meter_bar(:warning), do: "bg-warning"
  defp meter_bar(:error), do: "bg-error"
  defp meter_bar(:neutral), do: "bg-base-content/30"

  @doc """
  The selection bar of a list with checkboxes: « 3 sélectionnés » and the bulk
  actions, sticky at the bottom of the viewport (above the phone tab bar).
  Renders nothing while nothing is selected.

      <.bulk_bar id="members-bulk" count={MapSet.size(@selected)} clear="clear_selection">
        <:actions><button class="btn btn-primary btn-sm" phx-click="remind">Relancer</button></:actions>
      </.bulk_bar>
  """
  attr :id, :string, required: true
  attr :count, :integer, required: true

  attr :clear, :any,
    default: nil,
    doc: "event or `JS` clearing the selection: adds « Désélectionner »"

  slot :actions, required: true

  def bulk_bar(assigns) do
    ~H"""
    <div :if={@count > 0} id={@id} class="ta-bulkbar" role="region" aria-label={gettext("Sélection")}>
      <span class="text-sm font-semibold">
        {ngettext("%{count} sélectionné", "%{count} sélectionnés", @count)}
      </span>
      <button :if={@clear} type="button" class="btn btn-ghost btn-sm" phx-click={@clear}>
        {gettext("Désélectionner")}
      </button>
      <div class="ml-auto flex flex-wrap items-center justify-end gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  The amber « À compléter · 3 » block at the top of a page: what is left to do,
  one `attention_row/1` per item. Renders nothing when `count` is 0.

      <.attention_card id="todo" count={length(@todo)}>
        <.attention_row :for={t <- @todo} title={t.title} reason={t.reason}
          action="Désigner" navigate={t.path} />
      </.attention_card>
  """
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :title, :string, default: nil, doc: "default « À compléter » (« À régler » for fees)"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def attention_card(assigns) do
    ~H"""
    <section
      :if={@count > 0}
      id={@id}
      class={["rounded-box border border-warning/45 bg-warning/10 px-4 pb-1 pt-3", @class]}
    >
      <h2 class="flex items-center gap-2 text-sm font-semibold">
        <.icon name="hero-exclamation-triangle" class="size-4 text-warning" />
        {@title || gettext("À compléter")} · <span class="ta-num">{@count}</span>
      </h2>
      <ul class="flex flex-col">{render_slot(@inner_block)}</ul>
    </section>
    """
  end

  @doc """
  One thing to do: a title, the reason under it and its one action — the whole row
  is the action. A link with `navigate`/`patch`, a button with `phx-click`. On
  phones the action's label gives way to a chevron. `tone` adds a dot in front.
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :reason, :any, default: nil, doc: "the line under the title (nil/false: none)"
  attr :action, :string, required: true, doc: "the action's label (« Désigner »)"
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :tone, :atom, default: nil, values: [nil, :warning, :error, :info]
  attr :rest, :global

  def attention_row(assigns) do
    ~H"""
    <li id={@id} class="ta-row-rule last:border-b-0">
      <.link
        :if={@navigate || @patch}
        navigate={@navigate}
        patch={@patch}
        class="flex min-h-14 items-center gap-3 rounded-lg py-2.5 hover:no-underline sm:min-h-0"
        {@rest}
      >
        <.attention_row_body {assigns} />
      </.link>
      <button
        :if={!(@navigate || @patch)}
        type="button"
        class="flex min-h-14 w-full items-center gap-3 rounded-lg py-2.5 text-left sm:min-h-0"
        {@rest}
      >
        <.attention_row_body {assigns} />
      </button>
    </li>
    """
  end

  defp attention_row_body(assigns) do
    ~H"""
    <span :if={@tone} class={["size-2 shrink-0 rounded-full", dot_tone(@tone)]} aria-hidden="true"></span>
    <span class="flex min-w-0 flex-1 flex-col">
      <span class="text-[0.95rem] font-semibold leading-snug">{@title}</span>
      <span :if={@reason} class="text-[0.8rem] text-base-content/70">{@reason}</span>
    </span>
    <span class="btn btn-outline btn-xs hidden shrink-0 sm:inline-flex">{@action}</span>
    <span class="sr-only sm:hidden">{@action}</span>
    <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70 sm:hidden" />
    """
  end

  defp dot_tone(:warning), do: "bg-warning"
  defp dot_tone(:error), do: "bg-error"
  defp dot_tone(:info), do: "bg-info"

  @doc """
  A figure tile: label, the value in mono, a sub-line; with `navigate` the whole
  tile is a link (chevron after the label). `tone` colours the value.

      <.stat_tile id="kpi-calls" label="Appels aujourd'hui" value="12 / 14"
        sub="2 en retard" tone={:warn} navigate={~p"/school/day"} />
  """
  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :any, default: nil, doc: "the line under the value (nil/false: none)"
  attr :tone, :atom, default: :neutral, values: [:neutral, :ok, :warn, :error, :none]
  attr :navigate, :string, default: nil
  attr :class, :any, default: nil

  def stat_tile(assigns) do
    ~H"""
    <.link
      :if={@navigate}
      id={@id}
      navigate={@navigate}
      class={[
        "ta-section group flex flex-col gap-0.5 p-3 transition-colors hover:border-base-content/30 hover:no-underline sm:p-4",
        @class
      ]}
    >
      <.stat_tile_body {assigns} />
    </.link>
    <div :if={!@navigate} id={@id} class={["ta-section flex flex-col gap-0.5 p-3 sm:p-4", @class]}>
      <.stat_tile_body {assigns} />
    </div>
    """
  end

  defp stat_tile_body(assigns) do
    ~H"""
    <span class="flex items-center justify-between gap-2 text-[0.8rem] font-medium text-base-content/75">
      {@label}
      <.icon
        :if={@navigate}
        name="hero-chevron-right"
        class="size-3.5 opacity-50 transition-transform group-hover:translate-x-0.5"
      />
    </span>
    <span class={["ta-num text-2xl font-semibold leading-tight sm:text-3xl", value_tone(@tone)]}>
      {@value}
    </span>
    <span :if={@sub} class="text-xs text-base-content/70">{@sub}</span>
    """
  end

  defp value_tone(:neutral), do: nil
  defp value_tone(:ok), do: "text-primary"
  defp value_tone(:warn), do: "text-warning"
  defp value_tone(:error), do: "text-error"
  defp value_tone(:none), do: "text-base-content/70"
end
