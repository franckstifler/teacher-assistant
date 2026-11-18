defmodule TeacherAssistantWeb.School.RollCallHistoryLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{AttendanceStatus, RollCallHistory}
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: gettext("Historique des appels"))}

  def handle_params(%{"id" => id} = params, _uri, socket) do
    case RollCallHistory.load(socket.assigns.current_scope, id, params) do
      {:ok, history} ->
        view =
          if params["view"] == "students" and is_nil(history.date), do: :students, else: :sessions

        {:noreply, assign(socket, history: history, view: view)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Access denied."))
         |> push_navigate(to: ~p"/school/courses")}
    end
  end

  def handle_event("sequence", %{"seq" => seq}, socket) do
    %{history: history, view: view} = socket.assigns
    selected = Enum.find(history.sequences, &(&1.id == seq))
    {:noreply, push_patch(socket, to: history_path(history.context.id, selected, view))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["courses"]}
    >
      <section id="roll-call-history" class="mx-auto max-w-3xl space-y-5 pb-6">
        <.link
          navigate={~p"/school/courses"}
          class="inline-flex min-h-11 items-center gap-2 text-sm text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {gettext("Mes cours")}
        </.link>
        <.page_header
          title={gettext("Historique des appels")}
          subtitle={"#{@history.context.subject} · #{class_names(@history.classes)}"}
        />

        <form
          :if={@history.sequence}
          id="history-sequence-form"
          phx-change="sequence"
          class="max-w-sm"
        >
          <.input
            type="select"
            id="history-sequence"
            name="seq"
            label={gettext("Séquence")}
            value={@history.sequence.id}
            options={Enum.map(@history.sequences, &{sequence_label(&1), &1.id})}
          />
        </form>

        <div
          :if={@history.sequence && !@history.date}
          class="flex flex-wrap gap-2"
          aria-label={gettext("Historique des appels")}
        >
          <.link
            :for={
              {view, label} <- [{:sessions, gettext("Par séance")}, {:students, gettext("Par élève")}]
            }
            id={"history-view-#{view}"}
            patch={history_path(@history.context.id, @history.sequence, view)}
            aria-current={if @view == view, do: "page"}
            class={["btn min-h-11", if(@view == view, do: "btn-primary", else: "btn-ghost")]}
          >{label}</.link>
        </div>

        <details
          :if={@history.assessments != [] && !@history.date}
          id="history-assessments"
          class="ta-section px-4"
        >
          <summary class="cursor-pointer py-3 text-sm font-semibold">
            {gettext("Appels des jours d’évaluation")}
          </summary>
          <ul class="divide-y divide-base-300 pb-2">
            <li :for={assessment <- @history.assessments}>
              <.link
                patch={
                  history_path(@history.context.id, @history.sequence, :sessions, assessment.given_on)
                }
                class="flex flex-wrap items-center justify-between gap-x-3 py-3 text-sm text-primary"
              >
                <span>{assessment.label}</span><span>{Dates.short(assessment.given_on)}</span>
              </.link>
            </li>
          </ul>
        </details>

        <div :if={@history.date} class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="font-semibold">{Dates.short(@history.date)}</h2>
          <.link
            patch={history_path(@history.context.id, @history.sequence, :sessions)}
            class="btn btn-ghost min-h-11"
          >
            {gettext("Voir toute la séquence")}
          </.link>
        </div>

        <.empty_state
          :if={!@history.sequence && !@history.date}
          icon="hero-calendar-days"
          title={gettext("Aucune séquence configurée pour cette année scolaire.")}
        />

        <div
          :if={@view == :sessions && (@history.sequence || @history.date)}
          id="history-sessions"
          class="space-y-5"
        >
          <.empty_state
            :if={@history.sessions == []}
            icon="hero-clipboard-document-check"
            title={gettext("Aucun appel enregistré pour cette période.")}
          />
          <section
            :for={
              {week, sessions} <-
                Enum.chunk_by(@history.sessions, &Date.beginning_of_week(&1.date))
                |> Enum.map(&{Date.beginning_of_week(hd(&1).date), &1})
            }
            class="space-y-2"
          >
            <h2 :if={!@history.date} class="ta-eyebrow">
              {gettext("Semaine du %{date}", date: Dates.day_month(week))}
            </h2>
            <details
              :for={session <- sessions}
              id={"history-session-#{session.date}-#{session.period.id}"}
              class="ta-section px-4"
            >
              <summary class="cursor-pointer py-3 text-sm font-semibold">
                {Dates.short(session.date)} · {session.period.label} · {time(
                  session.period.start_time
                )}
                <span class="mt-1 block text-xs font-normal text-base-content/70">{session_counts(
                  session
                )}</span>
              </summary>
              <div
                :for={
                  {id, students} <-
                    Enum.sort_by(session.groups, fn {id, _} -> @history.classes[id] end)
                }
                class="space-y-1 border-t border-base-300 pb-3 pt-2"
              >
                <h3 class="text-sm font-medium">{@history.classes[id]}</h3>
                <ul class="divide-y divide-base-300/60">
                  <li
                    :for={student <- students}
                    class="flex flex-wrap justify-between gap-x-3 py-2 text-sm"
                  >
                    <span>{student.name}</span><span class="text-base-content/75">{status_label(
                      student
                    )}</span>
                  </li>
                </ul>
              </div>
            </details>
          </section>
        </div>

        <div :if={@view == :students} id="history-students" class="space-y-3">
          <p class="text-sm text-base-content/75">
            {gettext(
              "Le total inclut les présences, retards et absences enregistrés pour chaque élève. Les périodes sans statut sont exclues."
            )}
          </p>
          <.empty_state
            :if={@history.students == []}
            icon="hero-user-group"
            title={gettext("Aucun élève pour cette période.")}
          />
          <details
            :for={student <- @history.students}
            id={"history-student-#{student.context_id}-#{student.id}"}
            class="ta-section px-4"
          >
            <summary class="cursor-pointer py-3">
              <span class="font-semibold">{student.name}</span>
              <span class="ml-1 text-sm text-base-content/70">{@history.classes[student.context_id]}</span>
              <span class="ml-2 text-sm font-semibold text-primary">{presence(student)}</span>
              <span :if={student.history != []} class="mt-1 block text-xs text-base-content/70">{student_counts(
                student
              )}</span>
            </summary>
            <ul :if={student.history != []} class="divide-y divide-base-300 pb-2">
              <li
                :for={mark <- student.history}
                class="flex flex-wrap justify-between gap-x-3 py-2 text-sm"
              >
                <span>{Dates.short(mark.date)} · {mark.period.label}</span><span>{status_label(mark)}</span>
              </li>
            </ul>
          </details>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp history_path(id, sequence, view, date \\ nil) do
    params =
      [
        seq: sequence && sequence.id,
        view: if(view == :students, do: "students"),
        date: date && Date.to_iso8601(date)
      ]
      |> Enum.reject(fn {_, value} -> is_nil(value) end)

    ~p"/school/courses/#{id}/roll-calls?#{params}"
  end

  defp sequence_label(sequence),
    do:
      gettext("Séquence %{number} (%{first} au %{last})",
        number: sequence.number,
        first: Dates.day_month(sequence.start_date),
        last: Dates.day_month(sequence.end_date)
      )

  defp class_names(classes), do: classes |> Map.values() |> Enum.sort() |> Enum.join(", ")
  defp time(time), do: Calendar.strftime(time, "%H:%M")

  defp presence(%{total: 0}), do: gettext("Aucun pointage comptabilisé")

  defp presence(student),
    do: gettext("%{present}/%{total} présents", present: student.present, total: student.total)

  defp status_label(%{status: nil}), do: gettext("Non marqué")
  defp status_label(%{status: :absent, justified: true}), do: gettext("Absence justifiée")
  defp status_label(%{status: status}), do: AttendanceStatus.label(status)

  defp session_counts(session) do
    counts = session.groups |> Map.values() |> List.flatten() |> Enum.frequencies_by(& &1.status)

    gettext("%{present} présents · %{late} retards · %{absent} absences",
      present: Map.get(counts, :present, 0),
      late: Map.get(counts, :late, 0),
      absent: Map.get(counts, :absent, 0)
    )
  end

  defp student_counts(student) do
    gettext(
      "%{late} retards · %{absent} absences (%{justified} justifiées) · %{unmarked} non marqués · %{sent_home} renvois",
      late: student.late,
      absent: student.absent,
      justified: student.justified,
      unmarked: student.unmarked,
      sent_home: student.sent_home
    )
  end
end
