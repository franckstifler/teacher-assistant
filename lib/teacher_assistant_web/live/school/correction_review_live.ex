defmodule TeacherAssistantWeb.School.CorrectionReviewLive do
  @moduledoc """
  Censorat → Corrections de notes (spec D3c/D3a): requests awaiting a decision, those
  decided, and the marks journal. Admin axis only (Proviseur, Censeur).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Organization}
  alias TeacherAssistant.Academics.{Lock, MarkCorrectionMotive, MarkEntry}
  alias TeacherAssistantWeb.School.CorrectionsLive

  @tabs ~w(pending decided journal)

  def mount(_params, _session, socket) do
    if Assessment.can_decide_corrections?(socket.assigns.current_scope) do
      {:ok, assign(socket, selected: nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Réservé au censeur et au chef d'établissement."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "pending"
    {:noreply, socket |> assign(tab: tab, selected: nil) |> load_tab()}
  end

  def handle_event("select", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.corrections, &(&1.id == id))

    averages =
      selected && Assessment.correction_averages(socket.assigns.current_scope, selected)

    {:noreply,
     assign(socket, selected: selected, averages: averages, decision_form: decision_form())}
  end

  def handle_event("note", %{"decision" => params}, socket),
    do: {:noreply, assign(socket, decision_form: to_form(params, as: :decision))}

  def handle_event("approve", _params, socket),
    do: decide(socket, &Assessment.approve_correction/3, gettext("Correction acceptée."))

  def handle_event("refuse", _params, socket),
    do: decide(socket, &Assessment.refuse_correction/3, gettext("Correction refusée."))

  defp decide(%{assigns: %{selected: nil}} = socket, _fun, _message), do: {:noreply, socket}

  defp decide(socket, fun, message) do
    note = socket.assigns.decision_form[:note].value

    if String.length(String.trim(note || "")) > 500 do
      {:noreply, put_flash(socket, :error, gettext("La note dépasse 500 caractères."))}
    else
      record_decision(socket, fun, message, note)
    end
  end

  defp record_decision(socket, fun, message, note) do
    case fun.(socket.assigns.current_scope, socket.assigns.selected, note) do
      {:ok, _correction} ->
        {:noreply, socket |> put_flash(:info, message) |> assign(selected: nil) |> load_tab()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, error} ->
        message =
          if Exception.message(error) =~ "stale",
            do: gettext("La note a changé depuis la demande : demande à refaire."),
            else: gettext("Décision non enregistrée.")

        {:noreply, socket |> put_flash(:error, message) |> load_tab()}
    end
  end

  defp decision_form, do: to_form(%{"note" => ""}, as: :decision)

  defp load_tab(%{assigns: %{tab: "journal"}} = socket),
    do: assign(socket, corrections: [], journal: journal(socket.assigns.current_scope))

  defp load_tab(%{assigns: %{tab: tab}} = socket) do
    status = String.to_existing_atom(tab)
    assign(socket, corrections: Assessment.list_corrections(socket.assigns.current_scope, status))
  end

  # Journal lines, newest first: one per save (a batch of marks), per correction step,
  # and one derived "Verrouillage" line per locked séquence at its deadline.
  defp journal(scope) do
    events =
      scope
      |> Assessment.list_mark_events()
      |> Enum.chunk_by(&(&1.batch_id || &1.id))
      |> Enum.map(&event_line/1)

    locks =
      case scope.current_academic_year do
        nil ->
          []

        year ->
          for seq <- Organization.list_sequences(scope, year), Lock.locked?(seq) do
            %{
              id: "lock-#{seq.id}",
              at: lock_time(seq.grade_entry_deadline),
              who: gettext("Système"),
              what: gettext("Verrouillage"),
              detail: gettext("S%{n} · toutes les classes (date limite dépassée)", n: seq.number)
            }
          end
      end

    Enum.sort_by(events ++ locks, & &1.at, {:desc, DateTime})
  end

  # Midnight in Cameroon (UTC+1) the day after the deadline.
  defp lock_time(deadline),
    do: deadline |> Date.add(1) |> DateTime.new!(~T[00:00:00]) |> DateTime.add(-3600)

  defp event_line([event]) do
    %{
      id: event.id,
      at: event.inserted_at,
      who: author(event.actor),
      what: action_label(event.action),
      detail:
        Enum.join(
          [
            event.student && event.student.full_name,
            where(event),
            MarkEntry.format(event.before_status, event.before_score) <>
              " → " <> MarkEntry.format(event.after_status, event.after_score)
          ]
          |> Enum.reject(&is_nil/1),
          " · "
        )
    }
  end

  defp event_line([event | _] = batch) do
    %{
      id: event.id,
      at: event.inserted_at,
      who: author(event.actor),
      what: action_label(event.action),
      detail:
        Enum.join(
          Enum.reject([where(event), gettext("%{n} notes", n: length(batch))], &is_nil/1),
          " · "
        )
    }
  end

  defp where(%{assessment: %{teaching_context: tc} = a}) when not is_nil(tc),
    do: "#{a.label} · #{tc.subject} · #{tc.level}"

  defp where(_event), do: nil

  defp author(nil), do: gettext("Système")
  defp author(user), do: User.display_name(user)

  defp action_label(:saisie), do: gettext("Saisie")
  defp action_label(:correction_demandee), do: gettext("Correction demandée")
  defp action_label(:correction_approuvee), do: gettext("Correction approuvée")
  defp action_label(:correction_refusee), do: gettext("Correction refusée")

  defp value(status, score), do: MarkEntry.format(status, score)

  defp average(nil), do: "—"

  defp average(%Decimal{} = d),
    do:
      d
      |> Decimal.round(2)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

  defp local_time(%DateTime{} = at),
    do: at |> DateTime.add(3600) |> Calendar.strftime("%d/%m %H:%M")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="correction-review" class="space-y-6">
        <.page_header
          eyebrow={gettext("Censorat · intégrité des notes")}
          title={gettext("Corrections de notes")}
        />

        <nav role="tablist" class="tabs tabs-box w-fit">
          <.link
            :for={
              {tab, label} <- [
                {"pending", gettext("En attente")},
                {"decided", gettext("Traitées")},
                {"journal", gettext("Journal")}
              ]
            }
            id={"review-tab-#{tab}"}
            role="tab"
            patch={~p"/school/corrections/review?tab=#{tab}"}
            class={["tab", @tab == tab && "tab-active"]}
          >
            {label}
          </.link>
        </nav>

        <div :if={@tab == "pending"} class="grid gap-4 lg:grid-cols-[3fr_2fr]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table">
              <thead>
                <tr>
                  <th>{gettext("Date")}</th>
                  <th>{gettext("Enseignant")}</th>
                  <th>{gettext("Élève")}</th>
                  <th>{gettext("Évaluation")}</th>
                  <th>{gettext("Avant → après")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@corrections == []}>
                  <td colspan="5" class="text-center text-base-content/60">
                    {gettext("Aucune demande en attente.")}
                  </td>
                </tr>
                <tr
                  :for={c <- @corrections}
                  id={"pending-#{c.id}"}
                  phx-click="select"
                  phx-value-id={c.id}
                  class={[
                    "cursor-pointer transition hover:bg-base-200",
                    @selected && @selected.id == c.id && "bg-base-200"
                  ]}
                >
                  <td class="ta-num">{Calendar.strftime(c.inserted_at, "%d/%m")}</td>
                  <td>{c.requester && author(c.requester)}</td>
                  <td>{c.student.full_name} · {c.assessment.teaching_context.class_group.label}</td>
                  <td>{c.assessment.label}</td>
                  <td class="ta-num">
                    {value(c.current_status, c.current_score)} → {value(
                      c.requested_status,
                      c.requested_score
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside :if={@selected} id="correction-detail" class="ta-leaf space-y-3 p-4">
            <h2 class="font-display text-lg">
              {@selected.student.full_name} · {@selected.assessment.label}
            </h2>
            <dl class="grid grid-cols-2 gap-2 text-sm">
              <dt class="text-base-content/60">{gettext("Note actuelle")}</dt>
              <dd class="ta-num">{value(@selected.current_status, @selected.current_score)}</dd>
              <dt class="text-base-content/60">{gettext("Note demandée")}</dt>
              <dd class="ta-num font-semibold">
                {value(@selected.requested_status, @selected.requested_score)}
              </dd>
              <dt class="text-base-content/60">{gettext("Motif")}</dt>
              <dd>{MarkCorrectionMotive.label(@selected.motive)}</dd>
              <dt class="text-base-content/60">{gettext("Moyenne de séquence de l'élève")}</dt>
              <dd class="ta-num">
                {average(elem(@averages, 0))} → {average(elem(@averages, 1))}
              </dd>
            </dl>
            <.form for={@decision_form} id="decision-form" phx-change="note" class="space-y-2">
              <.input
                type="textarea"
                field={@decision_form[:note]}
                label={gettext("Note pour l'enseignant")}
                rows="2"
                maxlength="500"
              />
              <div class="flex gap-2">
                <button
                  id="approve-correction"
                  type="button"
                  phx-click="approve"
                  class="btn btn-primary btn-sm"
                >
                  {gettext("Accepter")}
                </button>
                <button
                  id="refuse-correction"
                  type="button"
                  phx-click="refuse"
                  class="btn btn-ghost btn-sm"
                >
                  {gettext("Refuser")}
                </button>
              </div>
            </.form>
          </aside>
        </div>

        <div
          :if={@tab == "decided"}
          class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
        >
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Décidée le")}</th>
                <th>{gettext("Enseignant")}</th>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Avant → après")}</th>
                <th>{gettext("Statut")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@corrections == []}>
                <td colspan="5" class="text-center text-base-content/60">
                  {gettext("Aucune demande traitée.")}
                </td>
              </tr>
              <tr :for={c <- @corrections} id={"decided-#{c.id}"}>
                <td class="ta-num">{c.decided_at && local_time(c.decided_at)}</td>
                <td>{c.requester && author(c.requester)}</td>
                <td>{c.student.full_name} · {c.assessment.teaching_context.class_group.label}</td>
                <td class="ta-num">
                  {value(c.current_status, c.current_score)} → {value(
                    c.requested_status,
                    c.requested_score
                  )}
                </td>
                <td><CorrectionsLive.correction_status status={c.status} /></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={@tab == "journal"}
          id="journal"
          class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
        >
          <table class="table">
            <thead>
              <tr>
                <th>{gettext("Horodatage")}</th>
                <th>{gettext("Auteur")}</th>
                <th>{gettext("Action")}</th>
                <th>{gettext("Détail")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@journal == []}>
                <td colspan="4" class="text-center text-base-content/60">
                  {gettext("Le journal est vide.")}
                </td>
              </tr>
              <tr :for={line <- @journal} id={"journal-#{line.id}"}>
                <td class="ta-num whitespace-nowrap">{local_time(line.at)}</td>
                <td>{line.who}</td>
                <td>{line.what}</td>
                <td class="ta-num">{line.detail}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
