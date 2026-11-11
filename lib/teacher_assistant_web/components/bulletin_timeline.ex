defmodule TeacherAssistantWeb.BulletinTimeline do
  @moduledoc """
  The road to a period's bulletins, as a teacher follows it (spec audit follow-ups
  A5, moved from the teacher's Bulletins view to « Mes cours »): each séquence's
  marks with its state and countdown, the class councils, the publication. On phones
  only the current step shows, a tap opens the rest.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import TeacherAssistantWeb.CoreComponents, only: [icon: 1]

  alias TeacherAssistant.Academics.Lock
  alias TeacherAssistantWeb.Dates

  @doc """
  The steps of a period: `[%{state: :done | :now | :later, title, sub}]` — each
  séquence's marks (locked, open with its deadline and J-n, or not open yet), then
  the councils (current once every séquence is locked), then the publication.
  """
  def steps(sequences, published?, today) do
    seq_steps = Enum.map(sequences, &sequence_step(&1, today))
    marks_done? = Enum.all?(seq_steps, &(&1.state == :done))

    seq_steps ++
      [
        %{
          state:
            cond do
              published? -> :done
              marks_done? -> :now
              true -> :later
            end,
          title: gettext("Conseils de classe"),
          sub: gettext("Après la clôture des notes")
        },
        %{
          state: if(published?, do: :done, else: :later),
          title: gettext("Publication des bulletins"),
          sub: gettext("Par l'administration")
        }
      ]
  end

  defp sequence_step(seq, today) do
    deadline = seq.grade_entry_deadline
    title = gettext("Notes de la séquence %{n}", n: seq.number)

    cond do
      Lock.locked?(seq, today) ->
        %{
          state: :done,
          title: title,
          sub: gettext("Verrouillées le %{date}", date: Dates.day_month(Date.add(deadline, 1)))
        }

      Lock.not_started?(seq, today) ->
        %{
          state: :later,
          title: title,
          sub: gettext("Ouvertes à partir du %{date}", date: Dates.day_month(seq.start_date))
        }

      true ->
        %{
          state: :now,
          title: title,
          sub:
            [
              gettext("Ouvertes jusqu'au %{date}", date: Dates.day_month(deadline)),
              Dates.countdown(deadline, today)
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" · ")
        }
    end
  end

  @doc "The step a phone shows first: the first current one, else the last done, else the first."
  def current_step(steps) do
    Enum.find(steps, &(&1.state == :now)) ||
      steps |> Enum.filter(&(&1.state == :done)) |> List.last() ||
      List.first(steps)
  end

  attr :id, :string, required: true
  attr :steps, :list, required: true

  @doc """
  The steps as a vertical timeline. Phones: a disclosure whose summary is the current
  step (`#<id>-current`); larger screens: the whole list (`#bulletin-steps`).
  """
  def timeline(assigns) do
    assigns = assign(assigns, :current, current_step(assigns.steps))

    ~H"""
    <section id={@id} aria-label={gettext("Étapes des bulletins")}>
      <details class="ta-section group sm:hidden">
        <summary
          id={"#{@id}-current"}
          class="flex min-h-12 cursor-pointer list-none items-center gap-3 px-4 py-2 [&::-webkit-details-marker]:hidden"
        >
          <span class={[
            "grid size-6 shrink-0 place-items-center rounded-full",
            step_dot(@current.state)
          ]}>
            <.icon :if={@current.state == :done} name="hero-check-mini" class="size-4" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col">
            <span class="text-[0.92rem] font-semibold">{@current.title}</span>
            <span class="ta-num text-xs text-base-content/70">{@current.sub}</span>
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 text-base-content/70 transition-transform group-open:rotate-180"
          />
        </summary>
        <div class="border-t border-base-300/60 px-4 pt-3">
          <.steps_list id={"#{@id}-phone-steps"} steps={@steps} />
        </div>
      </details>
      <div class="max-sm:hidden">
        <.steps_list id="bulletin-steps" steps={@steps} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :steps, :list, required: true

  defp steps_list(assigns) do
    ~H"""
    <ol id={@id} aria-label={gettext("Étapes")} class="flex flex-col">
      <li :for={{step, i} <- Enum.with_index(@steps)} data-state={step.state} class="flex gap-3">
        <span class="flex w-6 flex-col items-center">
          <span class={[
            "grid size-6 shrink-0 place-items-center rounded-full text-[0.7rem] font-semibold",
            step_dot(step.state)
          ]}>
            <.icon :if={step.state == :done} name="hero-check-mini" class="size-4" />
          </span>
          <span
            :if={i < length(@steps) - 1}
            class={[
              "min-h-4 w-0.5 flex-1",
              if(step.state == :done, do: "bg-primary", else: "bg-base-300")
            ]}
          ></span>
        </span>
        <span class="flex flex-1 flex-col gap-0.5 pb-3.5">
          <span class={[
            "text-[0.92rem] font-semibold",
            step.state == :later && "text-base-content/70"
          ]}>
            {step.title}
          </span>
          <span class="ta-num text-xs text-base-content/70">{step.sub}</span>
        </span>
      </li>
    </ol>
    """
  end

  defp step_dot(:done), do: "bg-primary text-primary-content"
  defp step_dot(:now), do: "border-2 border-warning"
  defp step_dot(:later), do: "border border-base-300"

  attr :id, :string, required: true
  attr :periods, :list, required: true, doc: "`[{param, label, period}]`"
  attr :current, :string, default: nil, doc: "the chosen period's param"
  attr :patch, :any, required: true, doc: "`fn param -> path end`"

  @doc "The trimester and year pills above the timeline."
  def period_pills(assigns) do
    ~H"""
    <nav id={@id} role="tablist" aria-label={gettext("Période")} class="ta-pills">
      <.link
        :for={{param, label, _} <- @periods}
        id={"period-#{String.replace(param, ":", "-")}"}
        role="tab"
        patch={@patch.(param)}
        aria-selected={to_string(param == @current)}
        aria-current={param == @current && "true"}
        class="ta-pill"
      >
        {label}
      </.link>
    </nav>
    """
  end
end
