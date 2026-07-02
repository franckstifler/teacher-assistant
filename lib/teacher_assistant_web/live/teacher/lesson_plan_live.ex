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
    to_form(%{
      "titre" => lesson_plan.titre,
      "duration_minutes" => lesson_plan.duration_minutes,
      "lesson_date" => lesson_plan.lesson_date,
      "competence_attendue" => lesson_plan.competence_attendue,
      "situation_probleme" => lesson_plan.situation_probleme,
      "objectifs" => lesson_plan.objectifs,
      "supports" => lesson_plan.supports,
      "prerequis" => lesson_plan.prerequis
    }, as: :lesson_plan)
  end

  def handle_event("save_header", %{"lesson_plan" => params}, socket) do
    {:ok, lesson_plan} = Academics.update_lesson_plan(socket.assigns.lesson_plan, params)

    {:noreply,
     socket
     |> assign(:lesson_plan, lesson_plan)
     |> assign(:header_form, header_form(lesson_plan))
     |> assign(:saved_at, DateTime.utc_now())}
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
          <span><span class="ta-eyebrow">{gettext("Discipline")}</span> {@ctx_bundle.ctx.subject}</span>
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
          phx-blur="save_header"
          phx-change="save_header"
          class="ta-leaf space-y-3"
        >
          <div class="grid gap-3 sm:grid-cols-2">
            <.input field={@header_form[:titre]} label={gettext("Titre de la leçon")} />
            <.input
              type="number"
              field={@header_form[:duration_minutes]}
              label={gettext("Durée (min)")}
              inputmode="numeric"
            />
          </div>
          <.input type="date" field={@header_form[:lesson_date]} label={gettext("Date")} />
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
          <.input type="textarea" field={@header_form[:supports]} label={gettext("Supports")} />
          <.input type="textarea" field={@header_form[:prerequis]} label={gettext("Prérequis")} />
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
