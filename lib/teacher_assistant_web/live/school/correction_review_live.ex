defmodule TeacherAssistantWeb.School.CorrectionReviewLive do
  @moduledoc """
  Censorat → Validation des corrections (spec D3c/D3a, Pilotage §2.7, UX refonte batch 5):
  requests awaiting a decision as full-width cards (« 7 → 17 », Refuser… / Approuver; a
  refusal needs a reason), a bulk « Approuver les N erreurs de saisie » (one traced
  decision each), those decided, and the marks journal folded under the cards. Admin
  axis only (Proviseur, Censeur).
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

  def handle_event("approve-typos", _params, socket) do
    typos = typos(socket.assigns.corrections)

    {approved, failed} =
      Assessment.approve_corrections(socket.assigns.current_scope, typos)

    socket =
      if approved > 0,
        do:
          put_flash(
            socket,
            :info,
            ngettext(
              "1 correction approuvée. Bulletins recalculés.",
              "%{count} corrections approuvées. Bulletins recalculés.",
              approved
            )
          ),
        else: socket

    socket =
      if failed > 0,
        do:
          put_flash(
            socket,
            :error,
            ngettext(
              "1 demande non enregistrée : la note a changé, demande à refaire.",
              "%{count} demandes non enregistrées : la note a changé, demandes à refaire.",
              failed
            )
          ),
        else: socket

    {:noreply, socket |> assign(refusing: nil, refuse_form: nil) |> load_tab()}
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
              kind: :lock,
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
      kind: event.action,
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
      kind: event.action,
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

  defp typos(corrections), do: Enum.filter(corrections, &(&1.motive == :erreur_saisie))

  # « Journal des notes · 3 saisies aujourd'hui, 1 verrouillage »
  defp journal_summary(journal) do
    today = Reference.today()

    entries =
      Enum.count(journal, fn line ->
        line.kind == :saisie and line.at |> DateTime.add(3600) |> DateTime.to_date() == today
      end)

    locks = Enum.count(journal, &(&1.kind == :lock))

    gettext("Journal des notes · %{entries}, %{locks}",
      entries: ngettext("%{count} saisie aujourd'hui", "%{count} saisies aujourd'hui", entries),
      locks: ngettext("%{count} verrouillage", "%{count} verrouillages", locks)
    )
  end

  def render(assigns) do
    assigns = assign(assigns, :typos, length(typos(assigns.corrections)))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="correction-review" class="mx-auto max-w-5xl space-y-5">
        <.page_header
          eyebrow={gettext("Notes verrouillées · chaque décision est tracée")}
          title={
            if @tab == "pending",
              do: gettext("Corrections à valider · %{count}", count: length(@corrections)),
              else: gettext("Corrections traitées")
          }
        >
          <:actions>
            <button
              :if={@tab == "pending" and @typos > 0}
              id="approve-typos"
              type="button"
              phx-click="approve-typos"
              data-confirm={
                ngettext(
                  "Approuver la demande motivée par une erreur de saisie ? La décision est tracée.",
                  "Approuver les %{count} demandes motivées par une erreur de saisie ? Chaque décision est tracée.",
                  @typos
                )
              }
              class="btn btn-outline"
            >
              {ngettext(
                "Approuver l'« erreur de saisie »",
                "Approuver les %{count} « erreurs de saisie »",
                @typos
              )}
            </button>
          </:actions>
        </.page_header>

        <.filter_pills id="review-tabs" label={gettext("Demandes")}>
          <:pill
            id="review-tab-pending"
            patch={~p"/school/corrections/review"}
            current={@tab == "pending"}
          >
            {gettext("En attente")}
          </:pill>
          <:pill
            id="review-tab-decided"
            patch={~p"/school/corrections/review?tab=decided"}
            current={@tab == "decided"}
          >
            {gettext("Traitées")}
          </:pill>
        </.filter_pills>

        <div :if={@tab == "pending"} class="space-y-4">
          <p :if={@corrections == []} class="ta-panel text-center text-base-content/70">
            {gettext("Aucune demande en attente.")}
          </p>

          <article
            :for={c <- @corrections}
            id={"correction-card-#{c.id}"}
            class="ta-panel flex flex-wrap items-center gap-x-6 gap-y-3"
          >
            <div class="flex min-w-0 flex-[1_1_18rem] flex-col gap-1">
              <p class="text-[0.95rem] font-semibold">
                {c.student.full_name}
                <span class="font-normal text-base-content/70">
                  · {c.assessment.teaching_context.class_group.label}
                </span>
              </p>
              <p class="text-sm text-base-content/75">
                {c.assessment.teaching_context.subject} · {gettext("Séq. %{n}",
                  n: c.assessment.sequence.number
                )} · {c.assessment.label} · {gettext("demandée par %{name} · %{when}",
                  name: (c.requester && author(c.requester)) || "—",
                  when: requested_at(c.inserted_at)
                )}
              </p>
              <p class="text-xs text-base-content/70">
                {gettext("Moyenne de séquence : %{change}", change: average_change(@averages[c.id]))}
              </p>
              <span class="badge badge-sm mt-1 border-base-300 bg-base-200 font-semibold">
                {MarkCorrectionMotive.label(c.motive)}
              </span>
            </div>

            <p
              class="ta-num flex items-center gap-2.5 text-2xl font-semibold sm:text-[1.7rem]"
              aria-label={change(c)}
            >
              <span class="text-base-content/60 line-through">{value(
                c.current_status,
                c.current_score
              )}</span>
              <span aria-hidden="true" class="text-base-content/60">→</span>
              <span>{value(c.requested_status, c.requested_score)}</span>
            </p>

            <.form
              :if={@refusing != c.id}
              for={to_form(%{"id" => c.id, "note" => ""}, as: :accept)}
              id={"accept-form-#{c.id}"}
              phx-submit="accept"
              class="flex flex-wrap items-center justify-end gap-2"
            >
              <input type="hidden" name="accept[id]" value={c.id} />
              <%!-- the optional note for the teacher, folded behind « Approuver » --%>
              <details class="dropdown dropdown-end">
                <summary
                  class="btn btn-ghost btn-square"
                  aria-label={gettext("Note pour l'enseignant")}
                  title={gettext("Note pour l'enseignant")}
                >
                  <.icon name="hero-chat-bubble-left-ellipsis" class="size-5" />
                </summary>
                <div class="dropdown-content z-30 mt-1 w-72 rounded-box border border-base-300 bg-base-100 p-3 shadow-xl">
                  <.input
                    type="text"
                    name="accept[note]"
                    id={"accept-note-#{c.id}"}
                    value=""
                    label={gettext("Note pour l'enseignant (facultatif)")}
                    maxlength="500"
                  />
                </div>
              </details>
              <button
                id={"refuse-#{c.id}"}
                type="button"
                phx-click="start-refuse"
                phx-value-id={c.id}
                class="btn btn-outline"
              >
                {gettext("Refuser…")}
              </button>
              <button type="submit" class="btn btn-primary">
                {gettext("Approuver")}
              </button>
            </.form>

            <.form
              :if={@refusing == c.id}
              for={@refuse_form}
              id={"refuse-form-#{c.id}"}
              phx-submit="refuse"
              class="basis-full space-y-2"
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
              <div class="flex flex-wrap justify-end gap-2">
                <button type="button" phx-click="cancel-refuse" class="btn btn-ghost btn-sm">
                  {gettext("Annuler")}
                </button>
                <button type="submit" class="btn btn-error btn-sm">
                  {gettext("Confirmer le refus")}
                </button>
              </div>
            </.form>
          </article>

          <details id="journal" class="ta-section group">
            <summary class="flex cursor-pointer list-none items-center gap-2 px-4 py-3.5 text-[0.95rem] font-semibold">
              <.icon
                name="hero-chevron-right"
                class="size-4 transition-transform group-open:rotate-90"
              />
              {journal_summary(@journal)}
            </summary>
            <p class="px-4 pb-2 text-sm text-base-content/70">
              {gettext("Toute modification après verrouillage est tracée.")}
            </p>
            <div class="overflow-x-auto border-t border-base-300">
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
          </details>
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
