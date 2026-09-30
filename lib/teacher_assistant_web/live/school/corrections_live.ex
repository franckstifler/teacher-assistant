defmodule TeacherAssistantWeb.School.CorrectionsLive do
  @moduledoc """
  Démarches → Corrections de notes (spec D3c): a teacher's requests to change locked
  marks, and the form to file one. Visiting marks the decisions as seen (menu badge).
  """
  use TeacherAssistantWeb, :live_view

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
     assign_form(socket, %{"assessment_id" => assessment_id, "motive" => "erreur_saisie"})}
  end

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
         |> put_flash(:info, gettext("Demande envoyée au censeur."))
         |> load_requests()
         |> assign_form(Map.take(params, ["assessment_id", "motive"]))}

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

  defp load_requests(socket),
    do: assign(socket, :requests, Assessment.list_my_corrections(socket.assigns.current_scope))

  # The form, with the students of the chosen assessment's class.
  defp assign_form(socket, params, errors \\ []) do
    errors = Enum.map(errors, fn {field, message} -> {field, {message, []}} end)

    assessment = Enum.find(socket.assigns.assessments, &(&1.id == params["assessment_id"]))

    students =
      if assessment,
        do:
          Enrollment.list_students(
            socket.assigns.current_scope,
            assessment.teaching_context.class_group
          ),
        else: []

    socket
    |> assign(:students, students)
    |> assign(:form, to_form(params, as: :correction, errors: errors))
  end

  defp first_id([%{id: id} | _]), do: id
  defp first_id([]), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="corrections-page" class="mx-auto max-w-3xl space-y-6">
        <.page_header
          eyebrow={gettext("Démarches · notes verrouillées")}
          title={gettext("Corrections de notes")}
        >
          <:actions>
            <span class="ta-num text-sm text-base-content/70">
              {gettext("%{n} en attente", n: Enum.count(@requests, &(&1.status == :pending)))}
            </span>
          </:actions>
        </.page_header>

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
                <td colspan="5" class="text-center text-base-content/60">
                  {gettext("Aucune demande pour l'instant.")}
                </td>
              </tr>
              <tr :for={c <- @requests} id={"correction-#{c.id}"}>
                <td class="ta-num">{Calendar.strftime(c.inserted_at, "%d/%m")}</td>
                <td>{c.student.full_name}</td>
                <td>{c.assessment.teaching_context.class_group.label} · {c.assessment.label}</td>
                <td class="ta-num">
                  {MarkEntry.format(c.current_status, c.current_score)} → {MarkEntry.format(
                    c.requested_status,
                    c.requested_score
                  )}
                </td>
                <td><.correction_status status={c.status} /></td>
              </tr>
            </tbody>
          </table>
        </div>

        <section class="ta-leaf space-y-4 p-4">
          <h2 class="font-display text-lg">{gettext("Nouvelle demande")}</h2>
          <p :if={@assessments == []} class="text-sm text-base-content/60">
            {gettext("Aucune évaluation verrouillée dans vos cours.")}
          </p>

          <.form
            :if={@assessments != []}
            for={@form}
            id="new-correction-form"
            phx-change="validate"
            phx-submit="request"
            class="space-y-3"
          >
            <div class="grid gap-3 sm:grid-cols-2">
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
                options={for s <- @students, do: {s.full_name, s.id}}
              />
            </div>
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
                  :for={motive <- MarkCorrectionMotive.values()}
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
            <button id="correction-submit" type="submit" class="btn btn-primary">
              {gettext("Envoyer au censeur")}
            </button>
            <p class="text-xs text-base-content/55">
              {gettext("Chaque demande et chaque décision sont inscrites au journal.")}
            </p>
          </.form>
        </section>
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
        :approved -> gettext("Approuvée")
        :refused -> gettext("Refusée")
      end}
    </span>
    """
  end
end
