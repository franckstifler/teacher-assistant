defmodule TeacherAssistantWeb.School.CorrectionsLive do
  @moduledoc """
  Démarches → Corrections de notes (spec D3c): a teacher's requests to change locked
  marks, and the form to file one. Visiting marks the decisions as seen (menu badge).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Enrollment}
  alias TeacherAssistant.Academics.{MarkCorrectionMotive, MarkEntry}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    :ok = Assessment.mark_corrections_seen(scope)

    {:ok,
     socket
     |> assign(:assessments, Assessment.list_correctable_assessments(scope))
     |> load_requests()}
  end

  def handle_params(params, _uri, socket) do
    assessment_id = params["assessment"] || first_id(socket.assigns.assessments)

    {:noreply,
     socket
     |> assign(:show_form?, socket.assigns.live_action == :new)
     |> assign_form(%{"assessment_id" => assessment_id, "motive" => "erreur_saisie"})}
  end

  def handle_event("open_form", _params, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/corrections/new")}

  def handle_event("validate", %{"correction" => params}, socket),
    do: {:noreply, assign_form(socket, params)}

  def handle_event("request", %{"correction" => params}, socket) do
    case MarkEntry.parse(params["value"]) do
      {:ok, entry} ->
        request(socket, params, entry)

      :error ->
        {:noreply,
         assign_form(socket, params,
           value: gettext("Note invalide : un nombre, abs, abj ou vide.")
         )}
    end
  end

  defp request(socket, params, entry) do
    {status, score} =
      case entry do
        :blank -> {nil, nil}
        {:graded, score} -> {:graded, score}
        absence -> {absence, nil}
      end

    attrs = %{
      assessment_id: params["assessment_id"],
      student_id: params["student_id"],
      requested_status: status,
      requested_score: score,
      motive: params["motive"]
    }

    case Assessment.request_correction(socket.assigns.current_scope, attrs) do
      {:ok, _correction} ->
        {:noreply,
         socket
         |> put_flash(:info, sent_message(socket.assigns.current_scope))
         |> load_requests()
         |> push_patch(to: ~p"/school/corrections")}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _error} ->
        {:noreply,
         assign_form(socket, params,
           value:
             gettext(
               "Demande impossible : la note doit être valide, différente de la note actuelle, et sans demande déjà en attente."
             )
         )}
    end
  end

  defp sent_message(scope) do
    case Assessment.censeur_name(scope) do
      nil -> gettext("Demande envoyée au censeur.")
      name -> gettext("Demande envoyée à %{name} (censeur).", name: name)
    end
  end

  defp load_requests(socket),
    do: assign(socket, :requests, Assessment.list_my_corrections(socket.assigns.current_scope))

  # The form, with the students of the chosen assessment's class.
  defp assign_form(socket, params, errors \\ []) do
    errors = Enum.map(errors, fn {field, message} -> {field, {message, []}} end)

    assessment = Enum.find(socket.assigns.assessments, &(&1.id == params["assessment_id"]))

    {students, current_marks} =
      if assessment do
        scope = socket.assigns.current_scope

        {Enrollment.list_students(scope, assessment.teaching_context.class_group),
         Map.new(Assessment.list_marks(scope, assessment), &{&1.student_id, &1})}
      else
        {[], %{}}
      end

    socket
    |> assign(:students, students)
    |> assign(:current_marks, current_marks)
    |> assign(:form, to_form(params, as: :correction, errors: errors))
  end

  defp current_mark(marks, student_id) do
    case marks[student_id] do
      nil -> MarkEntry.format(nil, nil)
      mark -> MarkEntry.format(mark.status, mark.score)
    end
  end

  # « 08 → 13 · … » once a student and a readable value are chosen.
  defp hint(%{current_marks: marks, form: form}) do
    with id when id not in [nil, ""] <- form[:student_id].value,
         raw when raw not in [nil, ""] <- form[:value].value,
         {:ok, entry} <- MarkEntry.parse(raw) do
      requested =
        case entry do
          :blank -> MarkEntry.format(nil, nil)
          {:graded, score} -> MarkEntry.format(:graded, score)
          status -> MarkEntry.format(status, nil)
        end

      "#{current_mark(marks, id)} → #{requested} · " <>
        gettext("Le bulletin n'est recalculé qu'après validation.")
    else
      _incomplete -> nil
    end
  end

  # « Par <name> le <date> », then « · <note> » when the admin left one.
  defp decision_line(%{status: :pending}), do: gettext("Envoyée au censeur")

  defp decision_line(c) do
    by =
      gettext("Par %{name} le %{date}",
        name: if(c.decider, do: User.display_name(c.decider), else: "—"),
        date: c.decided_at && Calendar.strftime(c.decided_at, "%d/%m")
      )

    if c.decision_note in [nil, ""], do: by, else: by <> " · " <> c.decision_note
  end

  defp first_id([%{id: id} | _]), do: id
  defp first_id([]), do: nil

  def render(assigns) do
    assigns = assign(assigns, :hint, hint(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="corrections-page" class="mx-auto max-w-4xl space-y-6">
        <.page_header
          eyebrow={gettext("Démarches · notes verrouillées")}
          title={gettext("Corrections de notes")}
          subtitle={
            gettext(
              "Une note verrouillée ne change qu'après validation du censeur. Tout est tracé."
            )
          }
        >
          <:actions>
            <button
              :if={!@show_form?}
              id="new-correction-button"
              type="button"
              phx-click="open_form"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Nouvelle demande")}
            </button>
          </:actions>
        </.page_header>

        <section :if={@show_form?} id="new-correction-panel" class="ta-leaf space-y-4 p-4">
          <h2 class="font-display text-lg">{gettext("Nouvelle demande")}</h2>
          <p :if={@assessments == []} class="text-sm text-base-content/70">
            {gettext("Aucune évaluation verrouillée dans vos cours.")}
          </p>

          <.form
            :if={@assessments != []}
            for={@form}
            id="new-correction-form"
            phx-change="validate"
            phx-submit="request"
            class="grid gap-3 sm:grid-cols-2"
          >
            <.input
              type="select"
              field={@form[:assessment_id]}
              label={gettext("Évaluation")}
              options={
                for a <- @assessments,
                    do:
                      {"#{a.teaching_context.class_group.label} · S#{a.sequence.number} · #{a.label}",
                       a.id}
              }
            />
            <.input
              type="select"
              field={@form[:student_id]}
              label={gettext("Élève")}
              options={
                for s <- @students,
                    do:
                      {"#{s.full_name} — #{gettext("note actuelle")} #{current_mark(@current_marks, s.id)}",
                       s.id}
              }
            />
            <.input
              field={@form[:value]}
              label={gettext("Nouvelle note (0–20, abs, abj ou vide)")}
              inputmode="decimal"
              autocomplete="off"
              class="ta-num input input-bordered w-32"
            />
            <fieldset class="space-y-1">
              <legend class="text-sm font-medium">{gettext("Motif")}</legend>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={motive <- MarkCorrectionMotive.offered()}
                  class={[
                    "btn btn-sm rounded-full transition",
                    if(@form[:motive].value == to_string(motive),
                      do: "btn-primary",
                      else: "btn-outline"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    name={@form[:motive].name}
                    value={motive}
                    checked={@form[:motive].value == to_string(motive)}
                    class="sr-only"
                  />
                  {MarkCorrectionMotive.label(motive)}
                </label>
              </div>
            </fieldset>
            <div class="flex flex-wrap items-center gap-3 sm:col-span-2">
              <button id="correction-submit" type="submit" class="btn btn-primary">
                {gettext("Envoyer la demande")}
              </button>
              <p :if={@hint} id="correction-hint" class="ta-num text-sm text-base-content/70">
                {@hint}
              </p>
            </div>
          </.form>
        </section>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="corrections-list" class="table">
            <thead>
              <tr>
                <th>{gettext("Date")}</th>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Classe")}</th>
                <th>{gettext("Avant → après")}</th>
                <th>{gettext("Statut")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@requests == []}>
                <td colspan="5" class="text-center text-base-content/70">
                  {gettext("Aucune demande pour l'instant.")}
                </td>
              </tr>
              <tr :for={c <- @requests} id={"correction-#{c.id}"}>
                <td class="ta-num">{Calendar.strftime(c.inserted_at, "%d/%m")}</td>
                <td>{c.student.full_name}</td>
                <td>{c.assessment.teaching_context.class_group.label} · {c.assessment.label}</td>
                <td class="ta-num whitespace-nowrap">
                  {MarkEntry.format(c.current_status, c.current_score)} → {MarkEntry.format(
                    c.requested_status,
                    c.requested_score
                  )}
                </td>
                <td>
                  <.correction_status status={c.status} />
                  <p data-role="decision" class="mt-1 text-xs text-base-content/70">
                    {decision_line(c)}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  def correction_status(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      case @status do
        :pending -> "badge-warning"
        :approved -> "badge-success"
        :refused -> "badge-error"
      end
    ]}>
      {case @status do
        :pending -> gettext("En attente")
        :approved -> gettext("Acceptée")
        :refused -> gettext("Refusée")
      end}
    </span>
    """
  end
end
