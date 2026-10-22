defmodule TeacherAssistantWeb.School.FeeControlComponents do
  @moduledoc """
  Fees 2 parts of the class fees page: the « Avis de retard » form for the class, the
  link to the printed warnings just issued, and the student card's return notes and
  warnings. Events are handled by `TeacherAssistantWeb.School.FeesLive`.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{Reference, ReturnNoteReason}
  alias TeacherAssistantWeb.Money

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  @doc "Print URL of a batch of warnings."
  def warnings_print_url(warnings),
    do: ~p"/school/fees/warnings/print?#{[ids: Enum.map_join(warnings, ",", & &1.id)]}"

  attr :rows, :list, required: true, doc: "roster rows of the students behind"
  attr :balances, :map, required: true
  attr :pay_by, Date, required: true
  attr :error, :string, default: nil

  def warn_class_form(assigns) do
    ~H"""
    <form
      id="warn-form"
      phx-submit="send_warnings"
      class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
    >
      <h2 class="font-semibold">{gettext("Avis de retard aux parents")}</h2>
      <p :if={@rows == []} class="text-sm text-base-content/70">
        {gettext("Aucun élève en retard.")}
      </p>
      <ul :if={@rows != []} class="space-y-1">
        <li :for={row <- @rows} class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="warn[ids][]"
            value={row.enrollment.id}
            checked
            class="checkbox checkbox-sm"
            id={"warn-#{row.enrollment.id}"}
          />
          <label for={"warn-#{row.enrollment.id}"} class="flex-1">{row.student.full_name}</label>
          <span class="ta-num text-base-content/70">
            {Money.format_fcfa(
              @balances[row.enrollment.id].due_to_date - @balances[row.enrollment.id].total_paid
            )}
          </span>
        </li>
      </ul>
      <label class="flex flex-wrap items-center gap-2 text-sm">
        {gettext("À régler avant le")}
        <input
          type="date"
          name="warn[pay_by]"
          value={Date.to_iso8601(@pay_by)}
          class="input input-sm w-44"
        />
      </label>
      <p :if={@error} id="warn-error" class="text-sm text-error">{@error}</p>
      <div class="flex gap-2">
        <button :if={@rows != []} type="submit" class="btn btn-primary btn-sm">
          {gettext("Émettre et imprimer")}
        </button>
        <button type="button" phx-click="warn_class" class="btn btn-ghost btn-sm">
          {gettext("Fermer")}
        </button>
      </div>
    </form>
    """
  end

  attr :warnings, :list, required: true

  def last_warnings(assigns) do
    ~H"""
    <div
      id="last-warnings"
      class="flex flex-wrap items-center gap-2 rounded-box bg-success/12 p-3 text-sm"
    >
      <span class="font-semibold">
        {ngettext("%{count} avis émis.", "%{count} avis émis.", length(@warnings))}
      </span>
      <a href={warnings_print_url(@warnings)} target="_blank" class="btn btn-primary btn-xs">
        <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer les avis")}
      </a>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :error, :string, default: nil
  attr :notes, :list, required: true
  attr :last_note, :map, default: nil
  attr :warnings, :list, required: true
  attr :last_warnings, :list, default: nil
  attr :can_edit?, :boolean, required: true

  def student_papers(assigns) do
    ~H"""
    <section id="return-notes" class="space-y-2">
      <h3 class="font-semibold">{gettext("Autorisation de retour")}</h3>

      <div :if={@last_note} id="last-note" class="space-y-2 rounded-box bg-success/12 p-3 text-sm">
        <p class="font-semibold">
          {gettext("Autorisation n° %{number} délivrée.", number: @last_note.number)}
        </p>
        <a
          href={~p"/school/fees/notes/#{@last_note.id}/print"}
          target="_blank"
          class="btn btn-primary btn-xs"
        >
          <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer l'autorisation")}
        </a>
      </div>

      <.form
        :if={@can_edit?}
        for={@form}
        id="note-form"
        phx-change="change_note"
        phx-submit="issue_note"
        class="space-y-1 rounded-box border border-base-300 p-3"
      >
        <.input
          field={@form[:reason]}
          type="select"
          options={Enum.map(ReturnNoteReason.values(), &{ReturnNoteReason.label(&1), &1})}
          label={gettext("Motif")}
        />
        <.input
          field={@form[:valid_until]}
          type="date"
          label={gettext("Valable jusqu'au")}
        />
        <.input field={@form[:internal_note]} label={gettext("Note interne (non imprimée)")} />
        <p :if={@error} id="note-error" class="text-sm text-error">{@error}</p>
        <button type="submit" class="btn btn-ghost btn-sm">{gettext("Délivrer l'autorisation")}</button>
      </.form>

      <div
        :for={n <- @notes}
        id={"note-#{n.id}"}
        class="space-y-1 rounded-box border border-base-300 p-2 text-sm"
      >
        <div class="flex items-center justify-between gap-2">
          <a href={~p"/school/fees/notes/#{n.id}/print"} target="_blank" class="link font-semibold">
            {n.number}
          </a>
          <span :if={n.status == :cancelled} class="badge badge-error badge-sm">{gettext("Annulée")}</span>
          <span
            :if={n.status == :valid and Date.compare(n.valid_until, Reference.today()) == :lt}
            class="badge badge-ghost badge-sm"
          >
            {gettext("Expirée")}
          </span>
        </div>
        <p class="text-base-content/70">
          {ReturnNoteReason.label(n.reason)} · {gettext("jusqu'au %{date}", date: date(n.valid_until))}
        </p>
        <form
          :if={@can_edit? and n.status == :valid}
          id={"cancel-note-#{n.id}"}
          phx-submit="cancel_note"
          class="flex gap-1"
        >
          <input type="hidden" name="note_id" value={n.id} />
          <input
            name="reason"
            placeholder={gettext("Raison de l'annulation")}
            aria-label={gettext("Raison de l'annulation")}
            class="input input-xs flex-1"
          />
          <button type="submit" class="btn btn-ghost btn-xs text-error">{gettext("Annuler")}</button>
        </form>
      </div>
    </section>

    <section id="student-warnings" class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        <h3 class="font-semibold">{gettext("Avis envoyés")}</h3>
        <button
          :if={@can_edit?}
          id="warn-student"
          type="button"
          phx-click="warn_student"
          class="btn btn-ghost btn-xs"
        >
          {gettext("Avertir les parents")}
        </button>
      </div>
      <.last_warnings :if={@last_warnings} warnings={@last_warnings} />
      <p :if={@warnings == []} class="text-sm text-base-content/70">{gettext("Aucun avis.")}</p>
      <div
        :for={w <- @warnings}
        id={"warning-#{w.id}"}
        class="space-y-1 rounded-box border border-base-300 p-2 text-sm"
      >
        <div class="flex items-center justify-between gap-2">
          <a href={warnings_print_url([w])} target="_blank" class="link font-semibold">{w.number}</a>
          <span class="ta-num">{Money.format_fcfa(w.total)}</span>
        </div>
        <div class="flex items-center justify-between gap-2 text-base-content/70">
          <span>{date(w.issued_on)} · {gettext("avant le %{date}", date: date(w.pay_by))}</span>
          <span :if={w.status == :cancelled} class="badge badge-error badge-sm">{gettext("Annulé")}</span>
        </div>
        <form
          :if={@can_edit? and w.status == :valid}
          id={"cancel-warning-#{w.id}"}
          phx-submit="cancel_warning"
          class="flex gap-1"
        >
          <input type="hidden" name="warning_id" value={w.id} />
          <input
            name="reason"
            placeholder={gettext("Raison de l'annulation")}
            aria-label={gettext("Raison de l'annulation")}
            class="input input-xs flex-1"
          />
          <button type="submit" class="btn btn-ghost btn-xs text-error">{gettext("Annuler")}</button>
        </form>
      </div>
    </section>
    """
  end
end
