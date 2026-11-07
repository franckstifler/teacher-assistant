defmodule TeacherAssistantWeb.Teacher.MarksComponents do
  @moduledoc """
  « Saisie des notes » pieces (spec 2026-10-09 §2.3, refonte 2026-11-03 Batch 1):
  one student row — a list row on phones, a table row from `sm` — its mark box
  saved on blur, the evaluation chips and cards, the save indicator, the side
  panel and the phone keypad.

  One mapping from a mark's state to its look (`mark_state/4`, `mark_box_class/1`)
  serves the phone row, the keypad card and the desktop cell.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{Appreciations, MarkEntry, Marks}

  @doc """
  A mark's state, for its look: `:error` (refused), `:absent`, `:excused`, `:fail`
  (under 10/20), `:pass`, `:next` (the next empty box) or `:empty`.
  """
  def mark_state(_entry, _max, error, _next?) when is_binary(error), do: :error
  def mark_state({:ok, :absent}, _max, _error, _next?), do: :absent
  def mark_state({:ok, :excused}, _max, _error, _next?), do: :excused

  def mark_state({:ok, {:graded, _}} = entry, max, _error, _next?),
    do: if(below_pass?(scaled(entry, max)), do: :fail, else: :pass)

  def mark_state(_entry, _max, _error, true), do: :next
  def mark_state(_entry, _max, _error, _next?), do: :empty

  @doc "The mark box's classes for a `mark_state/4` (72px on phones, 80px from `sm`)."
  def mark_box_class(state) do
    [
      "ta-num input h-11 w-[72px] px-2 text-center text-base font-semibold transition-colors",
      "sm:h-9 sm:w-20 sm:text-right sm:text-[0.95rem]",
      box_tone(state)
    ]
  end

  defp box_tone(:error), do: "input-error border-2 border-error text-error"
  defp box_tone(:absent), do: "border-error/50 bg-error/15 uppercase text-error"
  defp box_tone(:excused), do: "bg-base-200 uppercase text-base-content/70"
  defp box_tone(:fail), do: "text-error"
  defp box_tone(:next), do: "border-2 border-primary"
  defp box_tone(_state), do: nil

  @doc "The text colour of a mark shown large (keypad card) for a `mark_state/4`."
  def mark_tone(state) when state in [:error, :absent, :fail], do: "text-error"
  def mark_tone(:excused), do: "text-base-content/70"
  def mark_tone(_state), do: nil

  @doc """
  One student's row; `value` is the box text, `saved` the stored mark's text. On
  phones: number, name with the mention under it, the box, ✓ once saved. From
  `sm`: N°, name, box, ✓/⚠, appreciation, « ⋯ » (absent).
  """
  attr :student, :map, required: true
  attr :n, :integer, required: true
  attr :value, :string, default: ""
  attr :saved, :string, default: ""
  attr :error, :string, default: nil
  attr :locked?, :boolean, default: false
  attr :next?, :boolean, default: false
  attr :max, :any, required: true
  attr :grading_rules, :any, required: true

  def mark_row(assigns) do
    saved = MarkEntry.parse(assigns.saved)

    assigns =
      assign(assigns,
        saved_entry: saved,
        absent?: saved == {:ok, :absent},
        stored?: assigns.error == nil and assigns.saved not in [nil, ""],
        state:
          mark_state(MarkEntry.parse(assigns.value), assigns.max, assigns.error, assigns.next?)
      )

    ~H"""
    <tr
      id={"mark-row-#{@student.id}"}
      data-next={@next? && "true"}
      class={[
        "flex min-h-14 items-center gap-3 border-b border-base-300/60 px-4 py-1.5 transition-colors",
        "sm:table-row sm:min-h-0 sm:border-b-0 sm:p-0",
        @next? && "bg-primary/5"
      ]}
    >
      <td class="ta-num w-6 shrink-0 p-0 text-right text-xs text-base-content/70 sm:w-12 sm:px-4 sm:py-2 sm:text-left">
        {@n}
      </td>
      <td class="min-w-0 flex-1 p-0 sm:px-4 sm:py-2">
        <%!-- two lines on phones rather than cut: long names often differ only at the end --%>
        <span class="block text-[0.95rem] leading-snug max-sm:line-clamp-2 sm:truncate sm:text-sm">
          {@student.full_name}
        </span>
        <span class="block truncate text-xs sm:hidden">
          <span :if={@error} class="font-semibold text-error">{@error}</span>
          <.appreciation
            :if={!@error}
            entry={@saved_entry}
            max={@max}
            grading_rules={@grading_rules}
            compact
          />
        </span>
      </td>
      <td class="shrink-0 p-0 sm:w-28 sm:px-4 sm:py-1.5">
        <input
          id={"mark-input-#{@student.id}"}
          type="text"
          name="value"
          inputmode="decimal"
          autocapitalize="off"
          autocomplete="off"
          aria-label={@student.full_name}
          aria-invalid={@error && "true"}
          aria-describedby={@error && "mark-error-#{@student.id}"}
          placeholder="—"
          value={@value}
          phx-blur="save_mark"
          phx-value-student={@student.id}
          phx-mounted={JS.ignore_attributes(["inputmode"])}
          data-mark-input
          data-student={@student.id}
          disabled={@locked?}
          class={mark_box_class(@state)}
        />
      </td>
      <td class="flex w-5 shrink-0 justify-center p-0 sm:table-cell sm:w-10 sm:px-2 sm:py-2">
        <span :if={@error} class="text-error" title={gettext("Erreur")}>
          <.icon name="hero-exclamation-circle" class="size-4" />
          <span class="sr-only">{gettext("Erreur")}</span>
        </span>
        <span :if={!@error and @stored?} class="text-primary" title={gettext("Enregistrée")}>
          <.icon name="hero-check" class="size-4" />
          <span class="sr-only">{gettext("Enregistrée")}</span>
        </span>
      </td>
      <td id={"mark-appreciation-#{@student.id}"} class="hidden text-sm sm:table-cell sm:px-4 sm:py-2">
        <span :if={@error} id={"mark-error-#{@student.id}"} class="font-semibold text-error">
          {@error}
        </span>
        <.appreciation
          :if={!@error}
          entry={@saved_entry}
          max={@max}
          grading_rules={@grading_rules}
        />
      </td>
      <td class="hidden w-12 sm:table-cell sm:px-2 sm:py-0.5">
        <.action_menu
          :if={!@locked?}
          id={"row-menu-#{@student.id}"}
          label={gettext("Plus d'options pour %{name}", name: @student.full_name)}
          class="[&_.btn]:btn-sm"
        >
          <:item
            id={"absent-#{@student.id}"}
            icon="hero-user-minus"
            click={JS.push("toggle_absent", value: %{student: @student.id})}
            confirm={
              replaces_mark?(@saved_entry) && gettext("Remplacer la note saisie par « absent » ?")
            }
          >
            {if @absent?, do: gettext("Retirer l'absence"), else: gettext("Marquer absent")}
          </:item>
        </.action_menu>
      </td>
    </tr>
    """
  end

  @doc "The mention of a stored entry: the school's band, or the absence it records."
  attr :entry, :any, required: true
  attr :max, :any, required: true
  attr :grading_rules, :any, required: true
  attr :compact, :boolean, default: false, doc: "plain coloured text (phone row)"

  def appreciation(%{entry: {:ok, :absent}} = assigns),
    do: ~H|<span class="text-error">{gettext("Absent — rattrapage possible")}</span>|

  def appreciation(%{entry: {:ok, :excused}} = assigns),
    do: ~H|<span class="text-base-content/70">{gettext("Absence justifiée")}</span>|

  def appreciation(%{entry: {:ok, {:graded, _}} = entry} = assigns) do
    assigns =
      assign(assigns, :mention, Marks.mention(scaled(entry, assigns.max), assigns.grading_rules))

    ~H"""
    <span
      :if={@compact}
      class={if @mention && @mention.passed?, do: "text-base-content/70", else: "text-error"}
    >
      {@mention && @mention.label}
    </span>
    <.mention_badge :if={!@compact} mention={@mention} />
    """
  end

  def appreciation(%{compact: true} = assigns), do: ~H""
  def appreciation(assigns), do: ~H|<span class="text-base-content/70">—</span>|

  @doc "The school's appreciation bands as `[[from_on_20, label], …]`, for the keypad's live mention."
  def bands_json(grading_rules) do
    grading_rules
    |> Appreciations.bands()
    |> Enum.map(&[Decimal.to_float(&1.from), &1.label])
    |> Jason.encode!()
  end

  # The mark on /20, nil when not a number.
  defp scaled({:ok, {:graded, d}}, %Decimal{} = max),
    do: d |> Decimal.mult(20) |> Decimal.div(max)

  defp scaled(_entry, _max), do: nil

  # Marking absent over an entered mark or a justified absence loses it: ask first.
  defp replaces_mark?({:ok, {:graded, _}}), do: true
  defp replaces_mark?({:ok, :excused}), do: true
  defp replaces_mark?(_entry), do: false

  defp below_pass?(nil), do: false
  defp below_pass?(d), do: Decimal.compare(d, 10) == :lt

  @doc """
  « ✓ Enregistré · 10:42 » once something saved, « Erreur : n notes à corriger »
  while a box is refused, nothing before. `:pill` in a header, `:inline` in a line.
  `time?: false` drops the time (the keypad header, where it would squeeze the title).
  """
  attr :id, :string, default: nil
  attr :time?, :boolean, default: true
  attr :errors, :map, required: true
  attr :saved_at, :any, default: nil
  attr :variant, :atom, default: :pill, values: [:pill, :inline]

  def save_indicator(assigns) do
    ~H"""
    <p
      :if={@errors != %{}}
      id={@id}
      class={[
        "ta-num shrink-0 font-semibold text-warning",
        if(@variant == :pill,
          do: "rounded-full bg-warning/20 px-3 py-1 text-sm",
          else: "text-xs"
        )
      ]}
    >
      {ngettext(
        "Erreur : %{count} note à corriger",
        "Erreur : %{count} notes à corriger",
        map_size(@errors)
      )}
    </p>
    <p
      :if={@errors == %{} and @saved_at != nil}
      id={@id}
      class={[
        "ta-num flex shrink-0 items-center gap-1 font-semibold text-primary",
        if(@variant == :pill,
          do: "rounded-full bg-primary/15 px-3 py-1 text-sm",
          else: "text-xs"
        )
      ]}
    >
      <.icon name="hero-check" class="size-3.5" />
      {if @time?,
        do: gettext("Enregistré · %{time}", time: Calendar.strftime(@saved_at, "%H:%M")),
        else: gettext("Enregistré")}
    </p>
    """
  end

  @doc """
  One evaluation of the séquence: a chip on phones (« label · /20 » over « ✓ x/N »),
  a card with a progress bar from `sm`. Patches the page to it.
  """
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :current?, :boolean, default: false
  attr :patch, :string, required: true
  attr :variant, :atom, default: :chip, values: [:chip, :card]

  def eval_chip(%{variant: :chip} = assigns) do
    assigns = assign(assigns, :complete?, assigns.total > 0 and assigns.count >= assigns.total)

    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@current? && "page"}
      class={[
        "flex h-12 flex-none flex-col justify-center gap-0.5 rounded-[0.625rem] px-3.5 transition-colors",
        if(@current?,
          do: "bg-primary text-primary-content",
          else: "border border-base-300 bg-base-100 hover:border-base-content/30"
        )
      ]}
    >
      <span class="whitespace-nowrap text-[0.8rem] font-semibold">
        {@column.label} · /{max_text(@column)}
      </span>
      <span class={[
        "ta-num flex items-center gap-1 text-[0.7rem] font-semibold",
        !@current? && @complete? && "text-primary",
        !@current? && !@complete? && "text-base-content/70"
      ]}>
        <.icon :if={@complete?} name="hero-check" class="size-3" />{@count}/{@total}
      </span>
    </.link>
    """
  end

  def eval_chip(%{variant: :card} = assigns) do
    pct = if assigns.total > 0, do: min(div(assigns.count * 100, assigns.total), 100), else: 0

    tone =
      cond do
        assigns.total > 0 and assigns.count >= assigns.total -> :done
        assigns.count > 0 -> :partial
        true -> :none
      end

    assigns = assign(assigns, pct: pct, tone: tone)

    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@current? && "page"}
      class={[
        "flex min-w-[9.5rem] flex-col gap-1.5 rounded-box bg-base-100 px-3.5 py-2.5 transition-colors",
        if(@current?,
          do: "border-2 border-primary",
          else: "border border-base-300 hover:border-base-content/30"
        )
      ]}
    >
      <span class="whitespace-nowrap text-sm font-semibold">
        {@column.label} <span class="font-normal text-base-content/70">/{max_text(@column)}</span>
      </span>
      <span class={[
        "ta-num flex items-center gap-2 text-xs font-medium",
        @tone == :done && "text-primary",
        @tone == :partial && "text-warning",
        @tone == :none && "text-base-content/70"
      ]}>
        <span class="h-[3px] flex-1 overflow-hidden rounded-full bg-base-300" aria-hidden="true">
          <span
            class={[
              "block h-full rounded-full transition-[width] duration-500",
              if(@tone == :done, do: "bg-primary", else: "bg-warning")
            ]}
            style={"width: #{@pct}%"}
          ></span>
        </span>
        {@count}/{@total}
      </span>
    </.link>
    """
  end

  @doc "The maximum of an assessment as typed (« 20 », « 12,5 »)."
  def max_text(%{max_score: %Decimal{} = m}),
    do: m |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  def max_text(_column), do: "20"

  @doc """
  The side panel: entered / expected, provisional average (red under 10), what is
  left, the save state, the boxes to correct and a jump to the next empty box.
  """
  attr :title, :string, required: true
  attr :done, :integer, required: true
  attr :total, :integer, required: true
  attr :average, :string, required: true
  attr :average_low?, :boolean, default: false
  attr :missing, :string, default: nil
  attr :saved_at, :any, default: nil
  attr :to_fix, :list, default: [], doc: "names of the students whose box is refused"
  attr :next_empty, :string, default: nil, doc: "the next empty box's student id"

  def side_panel(assigns) do
    assigns =
      assign(
        assigns,
        :pct,
        if(assigns.total > 0, do: div(assigns.done * 100, assigns.total), else: 0)
      )

    ~H"""
    <div id="marks-side-panel" class="ta-leaf space-y-3">
      <p class="ta-eyebrow">{@title}</p>
      <p id="marks-progress" class="ta-num">
        <span class="text-3xl font-semibold">{@done}</span>
        <span class="text-base-content/70"> / {@total} {gettext("saisies")}</span>
      </p>
      <div class="h-1.5 overflow-hidden rounded-full bg-base-300">
        <div
          class={[
            "h-full rounded-full transition-all duration-500",
            if(@pct == 100, do: "bg-primary", else: "bg-warning")
          ]}
          style={"width: #{@pct}%"}
        >
        </div>
      </div>
      <p id="marks-average-preview" class="ta-num text-sm">
        {gettext("Moyenne provisoire :")}
        <span class={["font-semibold", if(@average_low?, do: "text-error", else: "text-primary")]}>
          {@average}
        </span>
      </p>
      <p :if={@missing} id="marks-missing" class="text-sm text-warning">{@missing}</p>
      <p
        :if={@to_fix == [] and @saved_at != nil}
        id="marks-saved-line"
        class="ta-num flex items-center gap-1.5 text-sm text-primary"
      >
        <.icon name="hero-check" class="size-4" />
        {gettext("Tout est enregistré · %{time}", time: Calendar.strftime(@saved_at, "%H:%M"))}
      </p>
      <p :if={@to_fix != []} id="marks-to-fix" class="text-sm text-error">
        {ngettext(
          "%{count} note à corriger (%{names})",
          "%{count} notes à corriger (%{names})",
          length(@to_fix),
          names: Enum.join(@to_fix, ", ")
        )}
      </p>
      <button
        :if={@next_empty}
        id="goto-next-empty"
        type="button"
        phx-click={JS.focus(to: "#mark-input-#{@next_empty}")}
        class="btn btn-primary btn-sm w-full"
      >
        {gettext("Aller à la prochaine note vide")}
      </button>
    </div>
    """
  end

  @doc """
  The phone keypad (spec 2026-11-03 Batch 1): the student in focus between the
  previous and next ones (dimmed), a 4×4 pad typing locally (`.MarksKeypad`), and
  « Suivant » saving through `save_mark`'s path before moving on.
  """
  attr :column, :map, required: true
  attr :course_title, :string, required: true
  attr :focus, :map, required: true, doc: "`%{student, class_group, n}` in focus"
  attr :prev_rows, :list, default: [], doc: "up to two rows before, same shape"

  attr :next_rows, :list,
    default: [],
    doc: "the rows after (clipped to the height left), same shape"

  attr :scores, :map, required: true
  attr :errors, :map, required: true
  attr :remaining, :integer, required: true, doc: "empty boxes left in the focus's class"
  attr :done, :integer, required: true
  attr :total, :integer, required: true
  attr :saved_at, :any, default: nil
  attr :grading_rules, :any, required: true

  def keypad(assigns) do
    %{focus: %{student: student}, scores: scores, column: column} = assigns
    value = Map.get(scores, student.id, "")
    error = assigns.errors[student.id]

    assigns =
      assign(assigns,
        value: value,
        error: error,
        state: mark_state(MarkEntry.parse(value), column.max_score, error, false),
        mention: keypad_mention(MarkEntry.parse(value), column.max_score, assigns.grading_rules)
      )

    ~H"""
    <div
      id="marks-keypad"
      role="dialog"
      aria-modal="true"
      aria-labelledby="marks-keypad-title"
      phx-hook=".MarksKeypad"
      data-student={@focus.student.id}
      data-value={@value}
      data-max={Decimal.to_string(@column.max_score, :normal)}
      data-bands={bands_json(@grading_rules)}
      data-absent={gettext("Absent — rattrapage possible")}
      data-excused={gettext("Absence justifiée")}
      class="fixed inset-0 z-50 flex flex-col bg-base-100 sm:hidden"
    >
      <header class="flex items-center gap-2 border-b border-base-300 bg-base-200 px-4 py-3">
        <button
          type="button"
          id="keypad-close"
          data-key="close"
          class="btn btn-ghost btn-square -ml-2"
          aria-label={gettext("Revenir à la liste")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
        <div class="min-w-0 flex-1">
          <p id="marks-keypad-title" class="truncate text-[0.95rem] font-semibold">
            {gettext("%{label} · sur %{max}", label: @column.label, max: max_text(@column))}
          </p>
          <%!-- the count never truncates: the course name gives way first on narrow phones --%>
          <p class="ta-num flex gap-1 text-xs text-base-content/70">
            <span class="min-w-0 truncate">{@course_title} · {@focus.class_group.label} ·</span>
            <span id="keypad-progress" class="shrink-0">
              {gettext("%{done}/%{total} saisies", done: @done, total: @total)}
            </span>
          </p>
        </div>
        <.save_indicator
          id="keypad-save-state"
          errors={@errors}
          saved_at={@saved_at}
          variant={:inline}
          time?={false}
        />
      </header>

      <%!-- The card never shrinks: on a short screen the previous rows give way
           first (keeping the nearest), and the next rows fill whatever height is left. --%>
      <div class="flex min-h-0 flex-1 flex-col gap-1 px-4 pt-2">
        <div
          id="keypad-prev"
          class="flex min-h-0 flex-col justify-end gap-1 overflow-hidden [mask-image:linear-gradient(to_top,black_80%,transparent)]"
        >
          <.keypad_neighbour :for={row <- @prev_rows} row={row} scores={@scores} />
        </div>
        <section
          id="keypad-card"
          aria-label={gettext("Élève en cours")}
          class="flex shrink-0 flex-col gap-3 rounded-2xl border-2 border-primary bg-base-200 px-4 py-4"
        >
          <div class="flex items-center gap-3 text-xs">
            <span class="ta-num font-semibold text-primary">
              {@focus.class_group.label} · {gettext("N° %{n}", n: @focus.n)}
            </span>
            <span class="flex-1"></span>
            <span id="keypad-remaining" class="text-base-content/70">
              {ngettext(
                "%{count} restant dans %{class}",
                "%{count} restants dans %{class}",
                @remaining,
                class: @focus.class_group.label
              )}
            </span>
          </div>
          <p id="keypad-student" class="line-clamp-2 text-[1.375rem] font-semibold leading-tight">
            {@focus.student.full_name}
          </p>
          <div class="ta-num flex items-baseline gap-1.5">
            <output
              id={"keypad-value-#{@focus.student.id}"}
              phx-update="ignore"
              data-keypad-display
              class={["min-w-[2ch] text-5xl font-semibold leading-none", mark_tone(@state)]}
            >{display_value(@value)}</output>
            <span class="h-10 w-0.5 animate-pulse self-center bg-primary" aria-hidden="true"></span>
            <span class="text-lg text-base-content/70">/ {max_text(@column)}</span>
            <span class="flex-1"></span>
            <span
              id={"keypad-mention-#{@focus.student.id}"}
              phx-update="ignore"
              data-keypad-mention
              class="truncate font-sans text-sm text-base-content/70"
            >{@mention}</span>
          </div>
          <p :if={@error} id="keypad-error" class="text-sm font-semibold text-error">{@error}</p>
        </section>
        <div
          id="keypad-next"
          class="flex min-h-0 flex-1 flex-col gap-1 overflow-hidden [mask-image:linear-gradient(to_bottom,black_75%,transparent)]"
        >
          <.keypad_neighbour :for={row <- @next_rows} row={row} scores={@scores} />
        </div>
      </div>

      <div
        role="group"
        aria-label={gettext("Pavé de saisie")}
        class="grid grid-cols-4 gap-2 border-t border-base-300 bg-base-200 px-3 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-3"
      >
        <.keypad_key :for={d <- ~w(7 8 9)} key={d}>{d}</.keypad_key>
        <.keypad_key key="back" kind={:side} label={gettext("Effacer")}>⌫</.keypad_key>
        <.keypad_key :for={d <- ~w(4 5 6)} key={d}>{d}</.keypad_key>
        <.keypad_key key="abs" kind={:absent} label={gettext("Absent")}>ABS</.keypad_key>
        <.keypad_key :for={d <- ~w(1 2 3)} key={d}>{d}</.keypad_key>
        <.keypad_key key="abj" kind={:side} label={gettext("Absence justifiée")}>ABJ</.keypad_key>
        <.keypad_key key="comma" label={gettext("Virgule")}>,</.keypad_key>
        <.keypad_key key="0">0</.keypad_key>
        <.keypad_key key="prev" kind={:side} label={gettext("Élève précédent")}>↑</.keypad_key>
        <.keypad_key
          key="next"
          kind={:next}
          label={gettext("Enregistrer et passer à l'élève suivant")}
        >
          {gettext("Suivant")}
        </.keypad_key>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".MarksKeypad">
        // Types the focused student's mark locally; « Suivant » / ↑ / ✕ send it to the
        // server (`keypad_next` / `keypad_prev` / `keypad_close`), which saves it
        // through the same path as a blurred box and moves the focus.
        const DIGITS = "0123456789"
        export default {
          mounted() {
            // Desktop width: the pad is hidden, so it has no business being open.
            if (getComputedStyle(this.el).display === "none") {
              this.pushEvent("keypad_close", {})
              return
            }
            // A row box focused under the pad would keep a stale value (LiveView
            // never patches a focused input): let it go first.
            const active = document.activeElement
            if (active && active !== document.body && active.blur) active.blur()
            this.busy = false
            this.queue = []
            this.sync(true)
            this.el.addEventListener("click", (e) => {
              const key = e.target.closest("[data-key]")
              if (key) { e.preventDefault(); this.press(key.dataset.key) }
            })
            this.onKey = (e) => {
              if (e.metaKey || e.ctrlKey || e.altKey) return
              const map = {Backspace: "back", Enter: "next", ArrowDown: "next", ArrowUp: "prev",
                           Escape: "close", ",": "comma", ".": "comma"}
              const key = DIGITS.includes(e.key) && e.key.length === 1 ? e.key : map[e.key]
              if (key) { e.preventDefault(); this.press(key) }
            }
            window.addEventListener("keydown", this.onKey)
          },
          updated() { this.sync(false) },
          destroyed() { if (this.onKey) window.removeEventListener("keydown", this.onKey) },
          sync(force) {
            if (force || this.el.dataset.student !== this.student) {
              this.student = this.el.dataset.student
              this.value = this.el.dataset.value || ""
            }
            this.render()
          },
          press(key) {
            // While the server has not answered a move, keys wait: they belong to
            // the student the server moves to, never to the one just sent.
            if (this.busy) { this.queue.push(key); return }
            const v = this.value
            const code = v === "abs" || v === "abj" || v === "a"
            if (key === "back") {
              this.value = code ? "" : v.slice(0, -1)
            } else if (key === "comma") {
              if (code || v === "") this.value = "0,"
              else if (!v.includes(",")) this.value = v + ","
            } else if (key === "abs" || key === "abj") {
              this.value = key
              this.render()
              return this.send("keypad_next")
            } else if (key === "next" || key === "prev" || key === "close") {
              return this.send("keypad_" + key)
            } else if (DIGITS.includes(key)) {
              const base = code ? "" : v
              const [, decimals] = base.split(",")
              if (base.replace(",", "").length >= 4 || (decimals && decimals.length >= 2)) return
              this.value = base === "0" ? key : base + key
            }
            this.render()
          },
          send(event) {
            this.busy = true
            this.pushEvent(event, {student: this.student, value: this.value}, () => {
              this.busy = false
              this.sync(false)
              const queued = this.queue
              this.queue = []
              queued.forEach((key) => this.press(key))
            })
          },
          render() {
            const display = this.el.querySelector("[data-keypad-display]")
            const mention = this.el.querySelector("[data-keypad-mention]")
            if (!display || !mention) return
            const v = this.value
            display.textContent = v === "" ? "—" : (v === "abs" || v === "abj" ? v.toUpperCase() : v)
            display.classList.toggle("text-base-content/40", v === "")
            let label = ""
            let low = false
            if (v === "abs") { label = this.el.dataset.absent; low = true }
            else if (v === "abj") { label = this.el.dataset.excused }
            else if (v !== "") {
              const n = parseFloat(v.replace(",", "."))
              const max = parseFloat(this.el.dataset.max)
              if (!isNaN(n) && max > 0) {
                const on20 = n * 20 / max
                low = on20 < 10 || n > max
                const bands = JSON.parse(this.el.dataset.bands || "[]")
                for (const [from, text] of bands) if (on20 >= from) label = text
                if (n > max) label = ""
              }
            }
            mention.textContent = label
            display.classList.toggle("text-error", low)
          }
        }
      </script>
    </div>
    """
  end

  defp keypad_mention({:ok, :absent}, _max, _rules), do: gettext("Absent — rattrapage possible")
  defp keypad_mention({:ok, :excused}, _max, _rules), do: gettext("Absence justifiée")

  defp keypad_mention({:ok, {:graded, _}} = entry, max, rules) do
    case Marks.mention(scaled(entry, max), rules) do
      %{label: label} -> label
      _ -> ""
    end
  end

  defp keypad_mention(_entry, _max, _rules), do: ""

  defp display_value(value) when value in [nil, ""], do: "—"
  defp display_value(value) when value in ["abs", "abj"], do: String.upcase(value)
  defp display_value(value), do: value

  attr :row, :map, required: true
  attr :scores, :map, required: true

  defp keypad_neighbour(assigns) do
    ~H"""
    <div class="flex items-center gap-3 rounded-[0.625rem] px-3 py-2 text-sm text-base-content/60">
      <span class="ta-num w-6 text-right">{@row.n}</span>
      <span class="min-w-0 flex-1 truncate">{@row.student.full_name}</span>
      <span class="ta-num uppercase">
        {display_value(Map.get(@scores, @row.student.id, ""))}
      </span>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :kind, :atom, default: :digit, values: [:digit, :side, :absent, :next]
  attr :label, :string, default: nil
  slot :inner_block, required: true

  defp keypad_key(assigns) do
    ~H"""
    <button
      type="button"
      id={"keypad-key-#{@key}"}
      data-key={@key}
      aria-label={@label}
      class={[
        "h-[3.375rem] select-none rounded-[0.625rem] font-semibold transition active:scale-95",
        key_class(@kind)
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp key_class(:digit), do: "ta-num bg-base-300 text-xl text-base-content"
  defp key_class(:side), do: "ta-num border border-base-content/20 text-sm text-base-content"
  defp key_class(:absent), do: "ta-num border border-error/50 bg-error/10 text-sm text-error"
  defp key_class(:next), do: "bg-primary text-[0.95rem] text-primary-content"
end
