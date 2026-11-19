defmodule TeacherAssistantWeb.School.MemberProfileComponents do
  @moduledoc "Teaching overview and timetable on the member page."
  use TeacherAssistantWeb, :html
  alias TeacherAssistant.Accounts.{MembershipStatus, Phone}
  alias TeacherAssistant.Academics.DayOfWeek

  import TeacherAssistantWeb.School.LessonComponents, only: [hm: 1]

  attr :member, :map, required: true

  # The drawer's header already shows a phone-only account's number: its call
  # button then says « Appeler » instead of repeating it. The copy status is the
  # member's own, so a message never shows on the next member opened.
  def contact_actions(assigns) do
    assigns = assign(assigns, :status_id, "member-copy-status-#{assigns.member.id}")

    ~H"""
    <div id="member-contact-actions" class="flex flex-wrap items-center gap-2">
      <a
        :if={@member.user.phone}
        id="member-call"
        href={"tel:#{@member.user.phone}"}
        class="btn btn-sm btn-ghost min-h-11"
      >
        <.icon name="hero-phone" class="size-4" />
        <span :if={@member.user.email} class="ta-num">{Phone.format(@member.user.phone)}</span>
        <span :if={!@member.user.email}>{gettext("Appeler")}</span>
      </a>
      <button
        :if={@member.user.phone}
        id="member-copy-phone"
        type="button"
        class="btn btn-sm btn-ghost min-h-11"
        phx-click={
          JS.dispatch("phx:copy",
            detail: %{
              text: @member.user.phone,
              status: @status_id,
              success: gettext("Numéro copié."),
              failure: gettext("Copie impossible. Sélectionnez le numéro pour le copier.")
            }
          )
        }
      >
        <.icon name="hero-clipboard-document" class="size-4" /> {gettext("Copier le numéro")}
      </button>
      <a
        :if={@member.user.email}
        id="member-email"
        href={"mailto:#{@member.user.email}"}
        class="btn btn-sm btn-ghost min-h-11"
      >
        <.icon name="hero-envelope" class="size-4" /> {gettext("Envoyer un e-mail")}
      </a>
      <span
        id={@status_id}
        class="w-full text-xs text-base-content/70 empty:hidden"
        role="status"
        aria-live="polite"
        phx-update="ignore"
      ></span>
    </div>
    """
  end

  attr :member_id, :string, required: true
  attr :tab, :string, required: true
  attr :timetable?, :boolean, required: true

  # Labels fit one line at 360px (« Résumé » stands for « Vue d'ensemble » on
  # phones). Each tab is a link to its own address, so the back button, a reload
  # and a shared link land on the same tab; the bar sticks to the top of the page.
  def profile_tabs(assigns) do
    assigns =
      assign(
        assigns,
        :tabs,
        [{"overview", gettext("Résumé"), gettext("Vue d'ensemble")}] ++
          if(assigns.timetable?,
            do: [{"timetable", gettext("Emploi du temps"), gettext("Emploi du temps")}],
            else: []
          ) ++
          [{"settings", gettext("Paramètres"), gettext("Paramètres")}]
      )

    ~H"""
    <div
      id="member-profile-tabs"
      phx-hook="MemberProfileTabs"
      role="tablist"
      aria-label={gettext("Fiche du membre")}
      class="sticky top-0 z-10 flex gap-1 overflow-x-auto border-b border-base-300 bg-base-100"
    >
      <.link
        :for={{value, short, long} <- @tabs}
        id={"member-tab-#{value}"}
        patch={~p"/school/members/#{@member_id}?tab=#{value}"}
        role="tab"
        aria-selected={to_string(@tab == value)}
        aria-controls={"member-panel-#{value}"}
        tabindex={if @tab == value, do: "0", else: "-1"}
        class={[
          "flex min-h-11 flex-1 items-center justify-center whitespace-nowrap border-b-2 px-2 py-2 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-primary",
          if(@tab == value,
            do: "border-primary text-primary",
            else: "border-transparent text-base-content/70 hover:text-base-content"
          )
        ]}
      >
        <span class="sm:hidden">{short}</span><span class="hidden sm:inline">{long}</span>
      </.link>
    </div>
    """
  end

  attr :profile, :any, required: true
  attr :member, :map, required: true
  attr :tab, :string, required: true
  attr :timetable?, :boolean, default: false, doc: "whether the timetable tab exists"
  attr :day, :atom, default: nil
  attr :today, :atom, default: nil, doc: "today's weekday"

  def academic_panels(assigns) do
    ~H"""
    <section
      id="member-panel-overview"
      role="tabpanel"
      aria-labelledby="member-tab-overview"
      hidden={@tab != "overview"}
      tabindex="0"
      class="space-y-5"
    >
      <p :if={@member.status} class="text-sm text-base-content/70">
        {MembershipStatus.label(@member.status)}
      </p>
      <%= case @profile do %>
        <% {:ok, profile} -> %>
          <p :if={profile.teaching?} class="ta-eyebrow">{profile.year.name}</p>
          <.overview profile={profile} />
        <% {:error, reason} -> %>
          <%!-- no year to pick for a member who does not teach --%>
          <.profile_error
            :if={reason != :no_year or :teacher in Map.get(@member, :roles, [])}
            reason={reason}
          />
        <% _ -> %>
      <% end %>
    </section>
    <section
      :if={@timetable?}
      id="member-panel-timetable"
      role="tabpanel"
      aria-labelledby="member-tab-timetable"
      hidden={@tab != "timetable"}
      tabindex="0"
      class="space-y-4"
    >
      <%= case @profile do %>
        <% {:ok, %{timetable?: true} = profile} -> %>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p class="ta-eyebrow">{profile.year.name}</p>
            <.link
              id="member-print-timetable"
              href={~p"/school/members/#{@member.id}/timetable/print"}
              target="_blank"
              rel="noopener"
              class="btn btn-sm btn-ghost min-h-11"
            >
              <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer l'emploi du temps")}
            </.link>
          </div>
          <.timetable profile={profile} day={@day} today={@today} />
        <% {:error, reason} -> %>
          <.profile_error reason={reason} />
        <% _ -> %>
      <% end %>
    </section>
    """
  end

  attr :reason, :atom, required: true

  defp profile_error(%{reason: :no_year} = assigns) do
    ~H"""
    <p data-profile-message class="rounded-lg border border-base-300 p-4 text-sm" role="status">
      {gettext(
        "Sélectionnez une année scolaire pour consulter les affectations et l'emploi du temps."
      )}
    </p>
    """
  end

  # Retrying cannot lift a refusal: no Retry button.
  defp profile_error(%{reason: :forbidden} = assigns) do
    ~H"""
    <p data-profile-message class="rounded-lg border border-base-300 p-4 text-sm" role="status">
      {gettext("Vous n'avez pas accès aux informations pédagogiques de ce membre.")}
    </p>
    """
  end

  defp profile_error(assigns) do
    ~H"""
    <div data-profile-message class="rounded-lg border border-base-300 p-4 text-sm" role="status">
      <p>{gettext("Les informations pédagogiques ne sont pas disponibles pour le moment.")}</p>
      <button
        type="button"
        class="btn btn-sm btn-ghost mt-2 min-h-11"
        phx-click="retry_member_profile"
      >
        {gettext("Réessayer")}
      </button>
    </div>
    """
  end

  attr :profile, :map, required: true

  defp overview(assigns) do
    ~H"""
    <section :if={@profile.teaching?} aria-label={gettext("Service hebdomadaire")}>
      <dl id="member-workload" class="divide-y divide-base-300 text-sm">
        <div class="flex justify-between gap-4 py-2">
          <dt>{gettext("Service attendu")}</dt><dd class="ta-num font-semibold">
            {if @profile.service.service,
              do: gettext("%{n} h/sem.", n: @profile.service.service),
              else: gettext("Non précisé")}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-2">
          <dt>{gettext("Heures affectées")}</dt><dd
            id="member-assigned-hours"
            class="ta-num font-semibold"
          >
            {gettext("%{n} h/sem.", n: @profile.service.load)}
          </dd>
        </div>
        <div :if={@profile.timetable?} class="flex justify-between gap-4 py-2">
          <dt>{gettext("Heures à l'emploi du temps")}</dt><dd
            id="member-scheduled-hours"
            class="ta-num font-semibold"
          >
            {gettext("%{n} h/sem.", n: @profile.scheduled)}
          </dd>
        </div>
      </dl>
      <p
        :if={@profile.service.service && @profile.service.load > @profile.service.service}
        id="member-service-over"
        class="mt-2 text-sm font-medium text-warning"
      >
        {gettext("%{n} h au-delà du service attendu",
          n: @profile.service.load - @profile.service.service
        )}
      </p>
      <p
        :if={@profile.timetable? && @profile.missing > 0}
        id="member-missing-hours"
        class="mt-2 text-sm font-medium text-warning"
      >
        {gettext("%{n} h restent à placer dans l'emploi du temps", n: @profile.missing)}
      </p>
      <p :if={@profile.timetable?} class="mt-2 text-xs text-base-content/60">
        {gettext(
          "Une heure correspond à une période de cours de l'école. Un cours regroupé compte une seule fois."
        )}
      </p>
    </section>
    <section :if={@profile.teaching?} id="member-assignments" class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="text-base font-semibold">{gettext("Matières et classes")}</h3>
        <.link
          :if={@profile.can_assign?}
          id="member-manage-assignments"
          navigate={~p"/school/settings/assignments"}
          class="link link-primary text-sm"
        >{gettext("Gérer les affectations")}</.link>
      </div>
      <p :if={@profile.subjects == []} class="text-sm text-base-content/70">
        {gettext("Aucune matière affectée pour cette année scolaire.")}
      </p>
      <ul class="divide-y divide-base-300">
        <li :for={subject <- @profile.subjects} data-subject class="py-3 first:pt-0">
          <div class="flex items-baseline justify-between gap-4">
            <h4 class="font-medium">{subject.subject}</h4><span class="ta-num shrink-0 text-sm">{gettext(
              "%{n} h/sem.",
              n: subject.hours
            )}</span>
          </div>
          <ul class="mt-1.5 space-y-1.5">
            <li
              :for={course <- subject.courses}
              id={"member-course-#{elem(course.key, 1)}"}
              data-placement={@profile.timetable? && course.placement}
              class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5 text-sm"
            >
              <span class="flex min-w-0 flex-wrap gap-x-2">
                <.link
                  :for={class <- course.classes}
                  navigate={~p"/school/classes/#{class.id}"}
                  class="link link-hover text-primary"
                >{class.label}</.link>
                <span :if={length(course.classes) > 1} class="text-base-content/60">{gettext(
                  "Cours regroupé"
                )}</span>
              </span>
              <span
                :if={@profile.timetable?}
                class={["ta-num shrink-0 text-xs", placement_class(course.placement)]}
              >
                {gettext("%{placed} / %{required} h placées",
                  placed: course.scheduled,
                  required: course.hours
                )}
              </span>
              <span
                :if={!@profile.timetable? and length(subject.courses) > 1}
                class="ta-num shrink-0 text-xs text-base-content/70"
              >
                {gettext("%{n} h/sem.", n: course.hours)}
              </span>
            </li>
          </ul>
        </li>
      </ul>
    </section>
    <section :if={@profile.form_classes != []} id="member-form-classes" class="space-y-2">
      <h3 class="text-base font-semibold">{gettext("Professeur principal")}</h3>
      <div class="flex flex-wrap gap-3">
        <.link
          :for={class <- @profile.form_classes}
          navigate={~p"/school/classes/#{class.id}"}
          class="link link-primary text-sm"
        >{class.label}</.link>
      </div>
    </section>
    """
  end

  # More lessons placed than the course's hours stands out; fewer is still to do.
  defp placement_class(:over), do: "font-semibold text-warning"
  defp placement_class(:under), do: "text-info"
  defp placement_class(:ok), do: "text-base-content/70"

  attr :profile, :map, required: true
  attr :day, :atom, default: nil
  attr :today, :atom, default: nil

  defp timetable(assigns) do
    ~H"""
    <p
      :if={@profile.scheduled == 0}
      id="member-timetable-empty"
      class="rounded-lg border border-base-300 p-4 text-sm text-base-content/70"
    >
      {gettext("Aucun cours placé dans l'emploi du temps pour cette année.")}
    </p>
    <div :if={@profile.scheduled > 0}>
      <div class="space-y-3 lg:hidden">
        <div
          id="member-day-strip"
          role="group"
          aria-label={gettext("Jour de cours")}
          class="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1"
        >
          <button
            :for={day <- @profile.days}
            id={"member-day-#{day}"}
            type="button"
            phx-click="member_day"
            phx-value-day={day}
            aria-pressed={to_string(day == @day)}
            aria-current={day == @today && "date"}
            class={[
              "flex min-h-11 min-w-12 shrink-0 items-center justify-center rounded-field border px-3 text-sm font-semibold transition-colors",
              cond do
                day == @day -> "border-primary bg-primary text-primary-content"
                day == @today -> "border-primary/60 text-primary hover:bg-base-content/5"
                true -> "border-base-300 hover:bg-base-content/5"
              end
            ]}
          >
            <span aria-hidden="true">{DayOfWeek.short_label(day)}</span><span class="sr-only">{DayOfWeek.label(
              day
            )}</span>
          </button>
        </div>
        <div id="member-day-lessons" class="divide-y divide-base-300">
          <p :if={Map.get(@profile.lessons, @day, []) == []} class="py-4 text-sm text-base-content/70">
            {gettext("Aucun cours ce jour.")}
          </p>
          <div :for={lesson <- Map.get(@profile.lessons, @day, [])} class="py-3">
            <p class="ta-num mb-1 flex flex-wrap items-center gap-2 text-xs text-base-content/70">
              {hm(lesson.period.start_time)} – {hm(lesson.period.end_time)}
              <.clash_marker
                :if={get_in(@profile.cells, [{@day, lesson.period.id}, :clash?])}
                id={"member-day-clash-#{lesson.period.id}-#{elem(lesson.unit, 1)}"}
              />
            </p>
            <.lesson lesson={lesson} />
          </div>
        </div>
      </div>
      <div class="hidden overflow-x-auto lg:block">
        <table id="member-week-grid" class="table table-sm w-full">
          <caption class="sr-only">{gettext("Emploi du temps hebdomadaire")}</caption>
          <thead>
            <tr>
              <th scope="col">{gettext("Heure")}</th><th :for={day <- @profile.days} scope="col">
                {DayOfWeek.label(day)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={period <- @profile.periods}>
              <th scope="row" class="ta-num whitespace-nowrap align-top text-xs">
                {hm(period.start_time)}<br />{hm(period.end_time)}
              </th>
              <td :for={day <- @profile.days} class="min-w-24 align-top">
                <span :if={period.kind == :break} class="text-xs text-base-content/50">{gettext(
                  "Pause"
                )}</span>
                <div
                  :for={cell <- List.wrap(Map.get(@profile.cells, {day, period.id}))}
                  class={["space-y-2", cell.clash? && "rounded bg-error/10 p-1"]}
                >
                  <.clash_marker :if={cell.clash?} id={"member-clash-#{day}-#{period.id}"} />
                  <div :for={lesson <- cell.lessons}>
                    <.lesson lesson={lesson} />
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  # Two distinct lessons in one slot: the teacher cannot be in both classes.
  defp clash_marker(assigns) do
    ~H"""
    <span id={@id} data-clash class="badge badge-error badge-soft badge-sm gap-1 font-medium">
      <.icon name="hero-exclamation-triangle" class="size-3" /> {gettext("Conflit d'horaire")}
    </span>
    """
  end

  attr :lesson, :map, required: true

  defp lesson(assigns) do
    ~H"""
    <p class="text-sm font-medium">{hd(@lesson.members).subject}</p>
    <p class="text-xs text-base-content/70">
      {Enum.map_join(@lesson.members, ", ", & &1.class_label)}
    </p>
    <p
      :for={
        room <- @lesson.members |> Enum.map(& &1.room_name) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      }
      class="text-xs text-base-content/60"
    >
      {room}
    </p>
    """
  end
end
