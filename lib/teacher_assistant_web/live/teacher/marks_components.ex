defmodule TeacherAssistantWeb.Teacher.MarksComponents do
  @moduledoc """
  « Saisie des notes » pieces (spec 2026-10-09 §2.3): one student row — the mark cell
  saved on blur, the Absent toggle, the appreciation — and the side panel.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{MarkEntry, Marks}

  @doc "One student's row; `value` is the cell text, `saved` the stored mark's text."
  attr :student, :map, required: true
  attr :n, :integer, required: true
  attr :value, :string, default: ""
  attr :saved, :string, default: ""
  attr :error, :string, default: nil
  attr :locked?, :boolean, default: false
  attr :max, :any, required: true
  attr :grading_rules, :any, required: true

  def mark_row(assigns) do
    saved = MarkEntry.parse(assigns.saved)
    absent? = saved == {:ok, :absent}

    assigns =
      assign(assigns,
        absent?: absent?,
        scaled: scaled(MarkEntry.parse(assigns.value), assigns.max),
        saved_entry: saved
      )

    ~H"""
    <tr
      id={"mark-row-#{@student.id}"}
      class={["transition-opacity", @absent? && "bg-error/5 opacity-60"]}
    >
      <td class="ta-num w-10 text-xs text-base-content/70">{@n}</td>
      <td class="min-w-0">
        <span class="block truncate">{@student.full_name}</span>
      </td>
      <td class="w-28">
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
          data-mark-input
          data-student={@student.id}
          disabled={@locked? or @absent?}
          class={[
            "ta-num input input-bordered input-sm h-9 w-20 text-right transition-colors",
            @error && "input-error border-error",
            !@error && below_pass?(@scaled) && "text-error"
          ]}
        />
      </td>
      <td class="w-28">
        <button
          id={"absent-#{@student.id}"}
          type="button"
          phx-click="toggle_absent"
          phx-value-student={@student.id}
          aria-pressed={to_string(@absent?)}
          data-confirm={
            replaces_mark?(@saved_entry) && gettext("Remplacer la note saisie par « absent » ?")
          }
          disabled={@locked?}
          class={[
            "btn btn-xs min-w-[72px] transition",
            if(@absent?,
              do: "border-error bg-error/20 text-error",
              else: "btn-outline border-base-300"
            )
          ]}
        >
          {gettext("Absent")}
        </button>
      </td>
      <td id={"mark-appreciation-#{@student.id}"} class="text-sm">
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
    </tr>
    """
  end

  attr :entry, :any, required: true
  attr :max, :any, required: true
  attr :grading_rules, :any, required: true

  defp appreciation(%{entry: {:ok, :absent}} = assigns),
    do: ~H|<span class="text-error">{gettext("Absent — rattrapage possible")}</span>|

  defp appreciation(%{entry: {:ok, :excused}} = assigns),
    do: ~H|<span class="text-base-content/70">{gettext("Absence justifiée")}</span>|

  defp appreciation(%{entry: {:ok, {:graded, _}} = entry} = assigns) do
    assigns =
      assign(assigns, :mention, Marks.mention(scaled(entry, assigns.max), assigns.grading_rules))

    ~H|<.mention_badge mention={@mention} />|
  end

  defp appreciation(assigns), do: ~H|<span class="text-base-content/70">—</span>|

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

  @doc "The side panel: entered / expected, provisional average, what is left."
  attr :title, :string, required: true
  attr :done, :integer, required: true
  attr :total, :integer, required: true
  attr :average, :string, required: true
  attr :missing, :string, default: nil

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
        <span class="text-base-content/70"> / {@total}</span>
        <span class="block text-xs text-base-content/70">{gettext("notes saisies")}</span>
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
        <span class="font-semibold text-primary">{@average}</span>
      </p>
      <p :if={@missing} id="marks-missing" class="text-sm text-warning">{@missing}</p>
    </div>
    """
  end
end
