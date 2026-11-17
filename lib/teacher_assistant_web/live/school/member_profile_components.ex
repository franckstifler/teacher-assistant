defmodule TeacherAssistantWeb.School.MemberProfileComponents do
  @moduledoc "Teaching overview and timetable inside the member drawer."
  use TeacherAssistantWeb, :html
  alias TeacherAssistant.Accounts.{MembershipStatus, Phone}
  alias TeacherAssistant.Academics.DayOfWeek

  attr :member, :map, required: true

  def contact_actions(assigns) do
    ~H"""
    <div id="member-contact-actions" class="flex flex-wrap items-center gap-2">
      <a
        :if={@member.user.phone}
        id="member-call"
        href={"tel:#{@member.user.phone}"}
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-phone" class="size-4" /> {Phone.format(@member.user.phone)}
      </a>
      <button
        :if={@member.user.phone}
        id="member-copy-phone"
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={
          JS.dispatch("phx:copy-contact",
            detail: %{
              text: @member.user.phone,
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
        class="btn btn-sm btn-ghost"
      >
        <.icon name="hero-envelope" class="size-4" /> {gettext("Envoyer un e-mail")}
      </a>
      <span
        id="member-copy-status"
        class="w-full text-xs text-base-content/70"
        role="status"
        aria-live="polite"
        phx-update="ignore"
      ></span>
    </div>
    """
  end

  attr :tab, :string, required: true
  attr :timetable?, :boolean, required: true

  def profile_tabs(assigns) do
    assigns =
      assign(
        assigns,
        :tabs,
        [{"overview", gettext("Vue d'ensemble")}] ++
          if(assigns.timetable?, do: [{"timetable", gettext("Emploi du temps")}], else: []) ++
          [{"settings", gettext("Paramètres")}]
      )

    ~H"""
    <div
      id="member-profile-tabs"
      phx-hook="MemberProfileTabs"
      role="tablist"
      aria-label={gettext("Fiche du membre")}
      class="flex gap-1 border-b border-base-300"
    >
      <button
        :for={{value, label} <- @tabs}
        id={"member-tab-#{value}"}
        type="button"
        role="tab"
        aria-selected={to_string(@tab == value)}
        aria-controls={"member-panel-#{value}"}
        tabindex={if @tab == value, do: "0", else: "-1"}
        phx-click="member_tab"
        phx-value-tab={value}
        class={[
          "min-h-11 flex-1 border-b-2 px-2 py-2 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-primary",
          if(@tab == value,
            do: "border-primary text-primary",
            else: "border-transparent text-base-content/70 hover:text-base-content"
          )
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  attr :profile, :any, required: true
  attr :member, :map, required: true
  attr :tab, :string, required: true
  attr :day, :atom, default: nil

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
          <p class="ta-eyebrow">{profile.year.name}</p>
          <.overview profile={profile} />
        <% {:error, reason} -> %>
          <.profile_error reason={reason} />
        <% _ -> %>
      <% end %>
    </section>
    <section
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
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer l'emploi du temps")}
            </.link>
          </div>
          <.timetable profile={profile} day={@day} />
        <% {:error, reason} -> %>
          <.profile_error reason={reason} />
        <% _ -> %>
      <% end %>
    </section>
    """
  end

  attr :reason, :atom, required: true

  defp profile_error(assigns) do
    ~H"""
    <div
      data-profile-message
      class="rounded-lg border border-base-300 p-4 text-sm"
      role="status"
    >
      <%= if @reason == :no_year do %>
        {gettext(
          "Sélectionnez une année scolaire pour consulter les affectations et l'emploi du temps."
        )}
      <% else %>
        <p>{gettext("Les informations pédagogiques ne sont pas disponibles pour le moment.")}</p>
        <button type="button" class="btn btn-sm btn-ghost mt-2" phx-click="retry_member_profile">{gettext(
          "Réessayer"
        )}</button>
      <% end %>
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
    <section id="member-assignments" class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="text-base font-semibold">{gettext("Matières et classes")}</h3>
        <.link
          :if={@profile.can_assign?}
          id="member-manage-assignments"
          navigate={~p"/school/settings/assignments"}
          class="link link-primary text-sm"
        >{gettext("Gérer les affectations")}</.link>
      </div>
      <p :if={@profile.assignments == []} class="text-sm text-base-content/70">
        {gettext("Aucune matière affectée pour cette année scolaire.")}
      </p>
      <ul class="divide-y divide-base-300">
        <li :for={assignment <- @profile.assignments} class="py-3 first:pt-0">
          <div class="flex items-baseline justify-between gap-4">
            <h4 class="font-medium">{assignment.subject}</h4><span class="ta-num shrink-0 text-sm">{gettext(
              "%{n} h/sem.",
              n: assignment.hours
            )}</span>
          </div>
          <div class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-sm">
            <.link
              :for={class <- assignment.classes}
              navigate={~p"/school/classes/#{class.id}"}
              class="link link-hover text-primary"
            >{class.label}</.link>
            <span :if={length(assignment.classes) > 1} class="text-base-content/60">{gettext(
              "Cours regroupé"
            )}</span>
          </div>
          <p :if={@profile.timetable?} class="mt-1 text-xs text-base-content/70">
            {gettext("%{placed} / %{required} h placées",
              placed: assignment.scheduled,
              required: assignment.hours
            )}
          </p>
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

  attr :profile, :map, required: true
  attr :day, :atom, default: nil

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
        <div class="flex flex-wrap gap-1" aria-label={gettext("Jour de cours")}>
          <button
            :for={day <- @profile.days}
            id={"member-day-#{day}"}
            type="button"
            phx-click="member_day"
            phx-value-day={day}
            aria-pressed={to_string(day == @day)}
            class={["btn btn-sm", if(day == @day, do: "btn-primary", else: "btn-ghost")]}
          >{DayOfWeek.label(day)}</button>
        </div>
        <div id="member-day-lessons" class="divide-y divide-base-300">
          <p :if={Map.get(@profile.lessons, @day, []) == []} class="py-4 text-sm text-base-content/70">
            {gettext("Aucun cours ce jour.")}
          </p>
          <div :for={lesson <- Map.get(@profile.lessons, @day, [])} class="py-3">
            <p class="ta-num mb-1 text-xs text-base-content/70">
              {hm(lesson.period.start_time)} – {hm(lesson.period.end_time)}
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
                  :for={
                    lesson <-
                      Enum.filter(Map.get(@profile.lessons, day, []), &(&1.period.id == period.id))
                  }
                  class="mb-2 last:mb-0"
                >
                  <.lesson lesson={lesson} />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
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

  defp hm(time), do: Calendar.strftime(time, "%H:%M")
end
