defmodule TeacherAssistantWeb.Teacher.LessonPlanLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"entry_id" => entry_id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_entry_with_context(entry_id, ws) do
      {:ok, bundle} ->
        {:ok, lesson_plan} = Academics.ensure_lesson_plan(bundle.entry, bundle.ctx)

        {:ok,
         socket
         |> assign(:ctx_bundle, bundle)
         |> assign(:lesson_plan, lesson_plan)
         |> assign(:steps, Academics.list_lesson_steps(lesson_plan))
         |> assign(:saved_at, nil)
         |> assign(:header_form, header_form(lesson_plan))}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  defp header_form(lesson_plan) do
    to_form(
      %{
        "titre" => lesson_plan.titre,
        "duration_minutes" => lesson_plan.duration_minutes,
        "lesson_date" => lesson_plan.lesson_date,
        "competence_attendue" => lesson_plan.competence_attendue,
        "situation_probleme" => lesson_plan.situation_probleme,
        "objectifs" => lesson_plan.objectifs,
        "supports" => lesson_plan.supports,
        "prerequis" => lesson_plan.prerequis
      },
      as: :lesson_plan
    )
  end

  def handle_event("save_header", %{"lesson_plan" => params}, socket) do
    {:ok, lesson_plan} = Academics.update_lesson_plan(socket.assigns.lesson_plan, params)

    {:noreply,
     socket
     |> assign(:lesson_plan, lesson_plan)
     |> assign(:header_form, header_form(lesson_plan))
     |> assign(:saved_at, DateTime.utc_now())}
  end

  def handle_event("add_step", _params, socket) do
    {:ok, _} = Academics.add_lesson_step(socket.assigns.lesson_plan)
    {:noreply, reload_steps(socket)}
  end

  def handle_event("save_step", %{"id" => id, "step" => params}, socket) do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan),
         {:ok, _} <- Academics.update_lesson_step(step, params) do
      {:noreply, socket |> reload_steps() |> assign(:saved_at, DateTime.utc_now())}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move_step", %{"id" => id, "dir" => dir}, socket)
      when dir in ["up", "down"] do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan) do
      {:ok, _} = Academics.move_lesson_step(step, String.to_existing_atom(dir))
      {:noreply, reload_steps(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan) do
      :ok = Academics.delete_lesson_step(step)
      {:noreply, reload_steps(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp reload_steps(socket) do
    assign(socket, :steps, Academics.list_lesson_steps(socket.assigns.lesson_plan))
  end

  defp fmt_min(nil), do: "—"
  defp fmt_min(n), do: "#{n}"

  defp steps_total(steps) do
    Enum.reduce(steps, 0, fn s, acc -> acc + (s.duration_minutes || 0) end)
  end

  defp over_budget?(steps, %{duration_minutes: dm}) when is_integer(dm),
    do: steps_total(steps) > dm

  defp over_budget?(_steps, _lesson_plan), do: false

  defp step_form(step) do
    to_form(
      %{
        "etape" => step.etape,
        "duration_minutes" => step.duration_minutes,
        "contenus" => step.contenus,
        "supports" => step.supports,
        "activites" => step.activites
      },
      as: :step,
      id: "step-#{step.id}"
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="lesson-plan" class="mx-auto max-w-3xl space-y-5">
        <.page_header
          eyebrow={gettext("Fiche de préparation")}
          title={@lesson_plan.titre || @ctx_bundle.entry.lesson_title}
        >
          <:actions>
            <.link
              id="fiche-print-link"
              href={~p"/teacher/entries/#{@ctx_bundle.entry.id}/fiche/print"}
              target="_blank"
              class="btn btn-outline btn-sm gap-2"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Print / Save as PDF")}
            </.link>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm text-base-content/70">
          <span>
            <span class="ta-eyebrow">{gettext("Discipline")}</span> {@ctx_bundle.ctx.subject}
          </span>
          <span><span class="ta-eyebrow">{gettext("Classe")}</span> {@ctx_bundle.ctx.level}</span>
          <span class="ta-num">
            <span class="ta-eyebrow">{gettext("Effectif")}</span> {@ctx_bundle.effectif}
          </span>
          <span><span class="ta-eyebrow">{gettext("Module")}</span> {@ctx_bundle.entry.module}</span>
          <span :if={@ctx_bundle.entry.famille_de_situations}>
            <span class="ta-eyebrow">{gettext("Famille de situations")}</span>
            {@ctx_bundle.entry.famille_de_situations}
          </span>
        </div>

        <p id="fiche-saved-indicator" class="text-xs text-base-content/50">
          <span :if={@saved_at}>
            <.icon name="hero-check-circle" class="inline size-3.5 text-success" />
            {gettext("Saved")}
          </span>
          <span :if={is_nil(@saved_at)}>{gettext("Autosaves as you type")}</span>
        </p>

        <.form
          for={@header_form}
          id="fiche-header-form"
          phx-change="save_header"
          phx-debounce="blur"
          class="ta-leaf space-y-4"
        >
          <div class="grid gap-3 sm:grid-cols-[1fr_7rem_10rem]">
            <.input field={@header_form[:titre]} label={gettext("Titre de la leçon")} />
            <.input
              type="number"
              field={@header_form[:duration_minutes]}
              label={gettext("Durée (min)")}
              inputmode="numeric"
            />
            <.input type="date" field={@header_form[:lesson_date]} label={gettext("Date")} />
          </div>

          <fieldset class="space-y-3 border-t border-base-300 pt-3">
            <legend class="ta-eyebrow">{gettext("Cadre pédagogique")}</legend>
            <.input
              type="textarea"
              field={@header_form[:competence_attendue]}
              label={gettext("Compétence attendue")}
            />
            <.input
              type="textarea"
              field={@header_form[:situation_probleme]}
              label={gettext("Situation problème")}
            />
            <.input type="textarea" field={@header_form[:objectifs]} label={gettext("Objectifs")} />
          </fieldset>

          <fieldset class="space-y-3 border-t border-base-300 pt-3">
            <legend class="ta-eyebrow">{gettext("Ressources")}</legend>
            <.input type="textarea" field={@header_form[:supports]} label={gettext("Supports")} />
            <.input type="textarea" field={@header_form[:prerequis]} label={gettext("Prérequis")} />
          </fieldset>
        </.form>

        <div class="space-y-3">
          <div class="flex items-center justify-between gap-2">
            <h2 class="ta-eyebrow">{gettext("Déroulement")}</h2>
            <p
              id="fiche-duration-check"
              class={[
                "ta-num inline-flex items-center gap-1 text-xs",
                if(over_budget?(@steps, @lesson_plan),
                  do: "font-semibold text-warning",
                  else: "text-base-content/60"
                )
              ]}
            >
              <.icon
                :if={over_budget?(@steps, @lesson_plan)}
                name="hero-exclamation-triangle"
                class="size-3.5"
              />
              {steps_total(@steps)} / {fmt_min(@lesson_plan.duration_minutes)} {gettext("min")}
            </p>
          </div>

          <table
            :if={@steps != []}
            id="lesson-steps"
            class="w-full border-separate border-spacing-y-1"
          >
            <caption class="sr-only">{gettext("Lesson steps")}</caption>
            <thead class="hidden md:table-header-group">
              <tr class="text-left">
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Étape")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Durée")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Contenus")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Supports")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Activités")}</th>
                <th scope="col" class="px-2 pb-1">
                  <span class="sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody class="block space-y-2 md:table-row-group">
              <tr
                :for={s <- @steps}
                id={"step-row-#{s.id}"}
                class="ta-leaf block md:table-row align-top"
              >
                <td class="block md:table-cell md:px-2 md:py-1" colspan="6">
                  <.form
                    for={step_form(s)}
                    phx-change="save_step"
                    phx-value-id={s.id}
                    phx-debounce="blur"
                    class="grid gap-2 md:grid-cols-[8rem_5rem_1fr_1fr_1fr_auto] md:items-start"
                  >
                    <.input field={step_form(s)[:etape]} placeholder={gettext("Étape")} />
                    <.input
                      type="number"
                      field={step_form(s)[:duration_minutes]}
                      placeholder={gettext("min")}
                      inputmode="numeric"
                    />
                    <.input
                      type="textarea"
                      field={step_form(s)[:contenus]}
                      placeholder={gettext("Contenus")}
                    />
                    <.input
                      type="textarea"
                      field={step_form(s)[:supports]}
                      placeholder={gettext("Supports")}
                    />
                    <.input
                      type="textarea"
                      field={step_form(s)[:activites]}
                      placeholder={gettext("Activités")}
                    />
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        id={"step-up-#{s.id}"}
                        phx-click="move_step"
                        phx-value-id={s.id}
                        phx-value-dir="up"
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-chevron-up" class="size-4" />
                        <span class="sr-only">{gettext("Move up")}</span>
                      </button>
                      <button
                        type="button"
                        id={"step-down-#{s.id}"}
                        phx-click="move_step"
                        phx-value-id={s.id}
                        phx-value-dir="down"
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-chevron-down" class="size-4" />
                        <span class="sr-only">{gettext("Move down")}</span>
                      </button>
                      <button
                        type="button"
                        id={"step-delete-#{s.id}"}
                        phx-click="delete_step"
                        phx-value-id={s.id}
                        data-confirm={gettext("Delete this step?")}
                        class="btn btn-ghost btn-xs text-error"
                      >
                        <.icon name="hero-trash" class="size-4" />
                        <span class="sr-only">{gettext("Delete")}</span>
                      </button>
                    </div>
                  </.form>
                </td>
              </tr>
            </tbody>
          </table>

          <.empty_state
            :if={@steps == []}
            icon="hero-list-bullet"
            title={gettext("Aucune étape — ajoutez la première phase.")}
          />

          <button
            id="step-add"
            type="button"
            phx-click="add_step"
            class="btn btn-outline btn-sm gap-2"
          >
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add step")}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
