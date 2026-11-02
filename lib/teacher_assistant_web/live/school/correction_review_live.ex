defmodule TeacherAssistantWeb.School.CorrectionReviewLive do
  @moduledoc """
  Censorat → Validation des corrections (spec D3c/D3a, Pilotage §2.7): requests awaiting a
  decision as cards (a refusal needs a reason), those decided, and the marks journal
  under the cards. Admin axis only (Proviseur, Censeur).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Organization}
  alias TeacherAssistant.Academics.{Lock, MarkCorrectionMotive, MarkEntry, Reference}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.CorrectionsLive

  @tabs ~w(pending decided)
  @max_note 500

  def mount(_params, _session, socket) do
    if Assessment.can_decide_corrections?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(
         page_title: gettext("Validation des corrections"),
         refusing: nil,
         refuse_form: nil,
         corrections: []
       )
       |> assign_empty()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Réservé au censeur et au chef d'établissement."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "pending"
    {:noreply, socket |> assign(tab: tab, refusing: nil, refuse_form: nil) |> load_tab()}
  end

  def handle_event("start-refuse", %{"id" => id}, socket),
    do: {:noreply, assign(socket, refusing: id, refuse_form: refuse_form(id, "", nil))}

  def handle_event("cancel-refuse", _params, socket),
    do: {:noreply, assign(socket, refusing: nil, refuse_form: nil)}

  def handle_event("accept", %{"accept" => %{"id" => id} = params}, socket) do
    note = params["note"]

    with_correction(socket, id, fn correction ->
      if too_long?(note) do
        {:noreply, put_flash(socket, :error, gettext("La note dépasse 500 caractères."))}
      else
        message =
          gettext("Correction acceptée : %{student} %{change}. Bulletin recalculé.",
            student: correction.student.full_name,
            change: change(correction)
          )

        record_decision(socket, &Assessment.approve_correction/3, correction, message, note)
      end
    end)
  end

  def handle_event("refuse", %{"refusal" => %{"id" => id} = params}, socket) do
    note = params["note"]

    with_correction(socket, id, fn correction ->
      case refusal_error(note) do
        nil ->
          record_decision(
            socket,
            &Assessment.refuse_correction/3,
            correction,
            gettext("Demande refusée. L'enseignant est prévenu."),
            note
          )

        error ->
          {:noreply, assign(socket, refusing: id, refuse_form: refuse_form(id, note, error))}
      end
    end)
  end

  defp with_correction(socket, id, fun) do
    case Enum.find(socket.assigns.corrections, &(&1.id == id)) do
      nil -> {:noreply, load_tab(socket)}
      correction -> fun.(correction)
    end
  end

  defp too_long?(note), do: String.length(String.trim(note || "")) > @max_note

  defp refusal_error(note) do
    cond do
      String.trim(note || "") == "" -> gettext("Indiquez le motif du refus.")
      too_long?(note) -> gettext("La note dépasse 500 caractères.")
      true -> nil
    end
  end

  # The error is rendered by the template, so the form carries only the values.
  defp refuse_form(id, note, error) do
    to_form(%{"id" => id, "note" => note || "", "error" => error}, as: :refusal)
  end

  defp record_decision(socket, fun, correction, message, note) do
    case fun.(socket.assigns.current_scope, correction, note) do
      {:ok, _correction} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(refusing: nil, refuse_form: nil)
         |> load_tab()}

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

  defp assign_empty(socket), do: assign(socket, journal: [], averages: %{})

  defp load_tab(%{assigns: %{tab: tab}} = socket) do
    scope = socket.assigns.current_scope
    corrections = Assessment.list_corrections(scope, String.to_existing_atom(tab))

    if tab == "pending" do
      averages = Map.new(corrections, &{&1.id, Assessment.correction_averages(scope, &1)})
      assign(socket, corrections: corrections, averages: averages, journal: journal(scope))
    else
      assign(socket, corrections: corrections, averages: %{}, journal: [])
    end
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

  defp change(c),
    do:
      value(c.current_status, c.current_score) <>
        " → " <> value(c.requested_status, c.requested_score)

  defp average_change({before, after_}), do: average(before) <> " → " <> average(after_)

  defp requested_at(%DateTime{} = at) do
    local = DateTime.add(at, 3600)

    "#{Dates.relative(DateTime.to_date(local), Reference.today())} #{Calendar.strftime(local, "%H:%M")}"
  end

  defp pending_count_label(count) do
    ngettext("%{count} demande en attente", "%{count} demandes en attente", count) <>
      " · " <> gettext("une note ne change qu'après votre décision")
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="correction-review" class="space-y-6">
        <.page_header
          eyebrow={gettext("Censorat · intégrité des notes")}
          title={gettext("Validation des corrections")}
          subtitle={if @tab == "pending", do: pending_count_label(length(@corrections))}
        />

        <nav role="tablist" class="tabs tabs-box w-fit">
          <.link
            :for={
              {tab, label} <- [{"pending", gettext("En attente")}, {"decided", gettext("Traitées")}]
            }
            id={"review-tab-#{tab}"}
            role="tab"
            patch={~p"/school/corrections/review?tab=#{tab}"}
            class={["tab", @tab == tab && "tab-active"]}
          >
            {label}
          </.link>
        </nav>

        <div :if={@tab == "pending"} class="space-y-8">
          <p :if={@corrections == []} class="ta-panel text-center text-base-content/70">
            {gettext("Aucune demande en attente.")}
          </p>

          <div class="grid gap-4 lg:grid-cols-2">
            <article :for={c <- @corrections} id={"correction-card-#{c.id}"} class="ta-leaf space-y-3">
              <div>
                <p class="font-semibold">{c.student.full_name}</p>
                <p class="text-sm text-base-content/70">
                  {c.assessment.teaching_context.class_group.label} · {c.assessment.teaching_context.subject} · {gettext(
                    "Séquence %{n}",
                    n: c.assessment.sequence.number
                  )} · {c.assessment.label}
                </p>
              </div>

              <p class="ta-num text-3xl">{change(c)}</p>
              <p class="text-sm text-base-content/70">
                {gettext("Moyenne de séquence : %{change}", change: average_change(@averages[c.id]))}
              </p>
              <span class="badge badge-outline">{MarkCorrectionMotive.label(c.motive)}</span>
              <p class="text-xs text-base-content/70">
                {gettext("Demandée par %{name} · %{when}",
                  name: (c.requester && author(c.requester)) || "—",
                  when: requested_at(c.inserted_at)
                )}
              </p>

              <.form
                :if={@refusing != c.id}
                for={to_form(%{"id" => c.id, "note" => ""}, as: :accept)}
                id={"accept-form-#{c.id}"}
                phx-submit="accept"
                class="space-y-2"
              >
                <input type="hidden" name="accept[id]" value={c.id} />
                <.input
                  type="text"
                  name="accept[note]"
                  id={"accept-note-#{c.id}"}
                  value=""
                  label={gettext("Note pour l'enseignant (facultatif)")}
                  maxlength="500"
                />
                <div class="flex flex-wrap gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">
                    <.icon name="hero-check" class="size-4" /> {gettext("Accepter")}
                  </button>
                  <button
                    id={"refuse-#{c.id}"}
                    type="button"
                    phx-click="start-refuse"
                    phx-value-id={c.id}
                    class="btn btn-ghost btn-sm"
                  >
                    {gettext("Refuser")}
                  </button>
                </div>
              </.form>

              <.form
                :if={@refusing == c.id}
                for={@refuse_form}
                id={"refuse-form-#{c.id}"}
                phx-submit="refuse"
                class="space-y-2"
              >
                <input type="hidden" name="refusal[id]" value={c.id} />
                <.input
                  type="textarea"
                  field={@refuse_form[:note]}
                  label={gettext("Motif du refus")}
                  rows="2"
                  maxlength="500"
                  required
                />
                <p :if={@refuse_form[:error].value} role="alert" class="text-sm text-error">
                  {@refuse_form[:error].value}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button type="submit" class="btn btn-error btn-sm">
                    {gettext("Confirmer le refus")}
                  </button>
                  <button type="button" phx-click="cancel-refuse" class="btn btn-ghost btn-sm">
                    {gettext("Annuler")}
                  </button>
                </div>
              </.form>
            </article>
          </div>

          <section id="journal" class="space-y-2">
            <h2 class="font-display text-lg">{gettext("Journal des notes")}</h2>
            <p class="text-sm text-base-content/70">
              {gettext("Toute modification après verrouillage est tracée.")}
            </p>
            <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
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
                    <td colspan="4" class="text-center text-base-content/70">
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
                <td colspan="5" class="text-center text-base-content/70">
                  {gettext("Aucune demande traitée.")}
                </td>
              </tr>
              <tr :for={c <- @corrections} id={"decided-#{c.id}"}>
                <td class="ta-num">{c.decided_at && local_time(c.decided_at)}</td>
                <td>{c.requester && author(c.requester)}</td>
                <td>{c.student.full_name} · {c.assessment.teaching_context.class_group.label}</td>
                <td class="ta-num">{change(c)}</td>
                <td><CorrectionsLive.correction_status status={c.status} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
