defmodule TeacherAssistantWeb.School.SanctionsLive do
  @moduledoc """
  SG → Sanctions (spec KLM4, L1; Vie scolaire redesign §2.4; UX refonte batch 5):
  the year's sanctions as list rows (« name · class », « type · date · reason », a
  « Famille à prévenir / prévenue » badge, one CTA « Marquer notifié » plus a `tel:`
  call link) under pills « À notifier · N » / « Toutes · N » and a class select (the
  type filter sits in a menu); a detail panel with the guardian and « Supprimer »;
  the « Nouvelle sanction » form (student, type, date, hours or days, reason) on the
  right. No SMS (deferred).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Attendance, Discipline, Enrollment}
  alias TeacherAssistant.Academics.{GuardianRelationship, Reference, SanctionType}
  alias TeacherAssistantWeb.{Authz, SanctionLabels}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      {:ok,
       assign(socket,
         page_title: gettext("Sanctions"),
         classes: Enrollment.list_class_groups(scope, scope.current_academic_year),
         types: Attendance.school_life_rules(scope).sanction_types_in_use,
         issuers: Accounts.member_names(scope),
         q: "",
         matches: [],
         entry: %{enrollment: nil, type: nil},
         selected: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    filters = %{
      class: Enum.find_value(socket.assigns.classes, &(&1.id == params["class"] && &1.id)),
      type: Enum.find(SanctionType.values(), &(Atom.to_string(&1) == params["type"])),
      notify: params["notify"] == "1",
      page: parse_page(params["page"])
    }

    {:noreply, socket |> assign(filters: filters) |> load()}
  end

  defp load(socket) do
    %{current_scope: scope, filters: f} = socket.assigns

    page =
      Discipline.list_school_sanctions(scope, scope.current_academic_year,
        class_group_id: f.class,
        type: f.type,
        to_notify: f.notify,
        offset: (f.page - 1) * 50
      )

    selected =
      socket.assigns.selected && Enum.find(page.results, &(&1.id == socket.assigns.selected.id))

    other =
      Discipline.count_school_sanctions(scope, scope.current_academic_year,
        class_group_id: f.class,
        type: f.type,
        to_notify: !f.notify
      )

    counts =
      if f.notify,
        do: %{notify: page.count || 0, all: other},
        else: %{notify: other, all: page.count || 0}

    assign(socket,
      page: page,
      selected: selected,
      counts: counts,
      year_total:
        if(f.class || f.type || f.notify,
          do: Discipline.count_school_sanctions(scope, scope.current_academic_year, []),
          else: page.count || 0
        ),
      families: Discipline.count_families_to_notify(scope, scope.current_academic_year)
    )
  end

  def handle_event("filter", params, socket) do
    f = socket.assigns.filters

    filters = %{
      f
      | class: blank_to_nil(params["class"]),
        type: Enum.find(SanctionType.values(), &(Atom.to_string(&1) == params["type"])),
        page: 1
    }

    {:noreply, push_patch(socket, to: filter_link(filters))}
  end

  def handle_event("select", %{"id" => id}, socket),
    do:
      {:noreply, assign(socket, selected: Enum.find(socket.assigns.page.results, &(&1.id == id)))}

  def handle_event("search", %{"q" => q}, socket) do
    matches =
      if String.length(String.trim(q)) >= 2 do
        scope = socket.assigns.current_scope

        Enrollment.list_school_students(scope, scope.current_academic_year, query: q).results
        |> Enum.take(8)
      else
        []
      end

    {:noreply, assign(socket, q: q, matches: matches)}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    enrollment = Enum.find(socket.assigns.matches, &(&1.id == id))

    {:noreply,
     assign(socket, entry: %{socket.assigns.entry | enrollment: enrollment}, matches: [], q: "")}
  end

  def handle_event("type", %{"type" => type}, socket) do
    type = Enum.find(socket.assigns.types, &(Atom.to_string(&1) == type))
    {:noreply, assign(socket, entry: %{socket.assigns.entry | type: type})}
  end

  def handle_event("add", %{"entry" => params}, socket) do
    %{entry: %{enrollment: enrollment, type: type}, current_scope: scope} = socket.assigns

    with %{} <- enrollment,
         true <- not is_nil(type),
         {:ok, date} <- Date.from_iso8601(params["date"] || "") do
      attrs = %{
        type: type,
        date: date,
        reason: blank_to_nil(params["reason"]),
        duration_days: parse_int(params["duration_days"]),
        duration_hours: parse_int(params["duration_hours"])
      }

      case Discipline.add_sanction(scope, enrollment, attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Sanction enregistrée."))
           |> assign(entry: %{enrollment: nil, type: nil})
           |> load()
           |> refresh_badge()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, :duration_required} ->
          {:noreply,
           put_flash(socket, :error, gettext("Indiquez la durée de la consigne, en heures."))}

        {:error, :invalid_duration} ->
          {:noreply, put_flash(socket, :error, gettext("Une consigne dure de 1 à 40 heures."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Sanction non enregistrée."))}
      end
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Choisissez un élève, un type et une date."))}
    end
  end

  def handle_event("notify", %{"id" => id}, socket) do
    with %{} = s <- Enum.find(socket.assigns.page.results, &(&1.id == id)),
         {:ok, _} <- Discipline.mark_parents_notified(socket.assigns.current_scope, s) do
      {:noreply, socket |> load() |> refresh_badge()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %{} = s <- Enum.find(socket.assigns.page.results, &(&1.id == id)),
         :ok <- Discipline.delete_sanction(s, scope: socket.assigns.current_scope) do
      {:noreply, socket |> assign(selected: nil) |> load() |> refresh_badge()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: String.trim(v)

  defp parse_int(v) do
    case Integer.parse(to_string(v || "")) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_page(v) do
    case Integer.parse(to_string(v || "")) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp page_link(filters, page), do: filter_link(%{filters | page: page})

  defp filter_link(filters) do
    query =
      [
        {"notify", if(filters.notify, do: "1")},
        {"class", filters.class},
        {"type", filters.type},
        {"page", if(filters.page > 1, do: filters.page)}
      ]
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    if query == [], do: ~p"/school/sanctions", else: ~p"/school/sanctions?#{query}"
  end

  # The rail badge (parents to notify) is computed on mount; refresh it after a change.
  defp refresh_badge(socket) do
    scope = socket.assigns.current_scope

    case scope.capabilities do
      %{space: %{key: key}} ->
        scope = TeacherAssistantWeb.Spaces.put_space(scope, Atom.to_string(key))
        assign(socket, current_scope: scope, scope: scope)

      _ ->
        socket
    end
  end

  defp type_note(:conseil_discipline),
    do:
      gettext(
        "Le conseil de discipline est convoqué par le chef d'établissement ; la décision sera ajoutée après la séance."
      )

  defp type_note(nil), do: nil

  defp type_note(_type),
    do: gettext("Les parents sont à prévenir : la sanction apparaît dans « À notifier ».")

  defp type_cell(s) do
    case SanctionLabels.duration(s) do
      nil -> SanctionType.label(s.type)
      text -> "#{SanctionType.label(s.type)} · #{text}"
    end
  end

  defp meta_cell(s) do
    [type_cell(s), Calendar.strftime(s.date, "%d/%m"), s.reason]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp guardian(sanction) do
    case sanction.enrollment.student.primary_guardian_link do
      %{guardian: g} -> g
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="sanctions" class="flex flex-col gap-4">
        <.page_header
          eyebrow={gettext("Vie scolaire")}
          title={gettext("Sanctions")}
          subtitle={
            gettext("Cette année · %{sanctions} · %{families}",
              sanctions: ngettext("%{count} sanction", "%{count} sanctions", @year_total),
              families:
                ngettext("%{count} famille à prévenir", "%{count} familles à prévenir", @families)
            )
          }
        />

        <div class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(300px,360px)]">
          <div class="flex min-w-0 flex-col gap-3">
            <div class="flex flex-wrap items-center gap-2">
              <.filter_pills id="sanction-pills" label={gettext("Sanctions")}>
                <:pill
                  id="pill-notify"
                  patch={filter_link(%{@filters | notify: true, page: 1})}
                  count={@counts.notify}
                  current={@filters.notify}
                >
                  {gettext("À notifier")}
                </:pill>
                <:pill
                  id="pill-all"
                  patch={filter_link(%{@filters | notify: false, page: 1})}
                  count={@counts.all}
                  current={!@filters.notify}
                >
                  {gettext("Toutes")}
                </:pill>
              </.filter_pills>
              <form
                id="sanction-filters"
                phx-change="filter"
                class="flex flex-1 flex-wrap items-center justify-end gap-2"
              >
                <.class_picker
                  id="sanction-class"
                  classes={@classes}
                  current={@filters.class}
                  stepper={false}
                  prompt={gettext("Toutes les classes")}
                  class="w-auto min-w-44"
                />
                <div class="dropdown dropdown-end">
                  <div
                    tabindex="0"
                    role="button"
                    class={["btn btn-sm", if(@filters.type, do: "btn-primary", else: "btn-ghost")]}
                    aria-label={gettext("Filtrer par type")}
                  >
                    <.icon name="hero-funnel" class="size-4" />
                    <span :if={@filters.type}>{SanctionType.label(@filters.type)}</span>
                  </div>
                  <div
                    tabindex="-1"
                    class="dropdown-content z-30 mt-1 w-64 rounded-box border border-base-300 bg-base-100 p-3 shadow-xl"
                  >
                    <select
                      name="type"
                      aria-label={gettext("Type de sanction")}
                      class="select select-sm w-full"
                    >
                      <option value="">{gettext("Tous les types")}</option>
                      <option
                        :for={t <- SanctionType.values()}
                        value={t}
                        selected={t == @filters.type}
                      >
                        {SanctionType.label(t)}
                      </option>
                    </select>
                  </div>
                </div>
              </form>
            </div>

            <aside
              :if={@selected}
              id="sanction-panel"
              class="ta-panel flex min-w-0 flex-col gap-2 !border-primary"
            >
              <div class="flex items-start justify-between gap-2">
                <.link
                  navigate={~p"/school/students/#{@selected.enrollment.student_id}"}
                  class="font-display text-lg font-semibold hover:text-primary"
                >
                  {@selected.enrollment.student.full_name}
                </.link>
                <button
                  type="button"
                  phx-click="select"
                  phx-value-id=""
                  class="btn btn-ghost btn-square btn-sm"
                  aria-label={gettext("Fermer")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <span class="text-sm">
                {@selected.enrollment.class_group.label} · {type_cell(@selected)} · {date(
                  @selected.date
                )}
              </span>
              <span :if={@selected.reason} class="text-sm">{@selected.reason}</span>
              <span :if={@issuers[@selected.issued_by_user_id]} class="text-xs text-base-content/70">
                {gettext("Par %{name}", name: @issuers[@selected.issued_by_user_id])}
              </span>
              <span :if={@selected.parents_notified_on} class="text-sm text-primary">
                {gettext("Famille prévenue le %{date}", date: date(@selected.parents_notified_on))}
              </span>
              <%= case guardian(@selected) do %>
                <% nil -> %>
                  <.link
                    navigate={~p"/school/students/#{@selected.enrollment.student_id}"}
                    class="link text-sm text-warning"
                  >
                    {gettext("Aucun contact")}
                  </.link>
                <% g -> %>
                  <span class="text-sm">
                    {g.full_name} · {GuardianRelationship.label(g.relationship)}
                    <a href={"tel:#{g.phone_key}"} class="link link-primary font-mono">{g.phone}</a>
                    <a :if={g.phone_2} href={"tel:#{g.phone_2}"} class="link link-primary font-mono">{g.phone_2}</a>
                  </span>
              <% end %>
              <div class="flex flex-wrap gap-2 pt-1">
                <button
                  :if={!@selected.parents_notified_on}
                  id={"notify-#{@selected.id}"}
                  phx-click="notify"
                  phx-value-id={@selected.id}
                  class="btn btn-primary btn-sm"
                >
                  {gettext("Marquer notifié")}
                </button>
                <button
                  id={"delete-#{@selected.id}"}
                  phx-click="delete"
                  phx-value-id={@selected.id}
                  data-confirm={gettext("Supprimer cette sanction ?")}
                  class="btn btn-ghost btn-sm text-error"
                >
                  {gettext("Supprimer")}
                </button>
              </div>
            </aside>

            <div class="ta-section">
              <ul id="sanction-rows">
                <li
                  :for={s <- @page.results}
                  id={"sanction-#{s.id}"}
                  class={[
                    "ta-list-row flex-wrap gap-y-2",
                    @selected && @selected.id == s.id && "ta-list-row--selected"
                  ]}
                >
                  <%!-- the identity opens the detail panel; the CTA and the call link sit beside it --%>
                  <button
                    id={"open-#{s.id}"}
                    type="button"
                    phx-click="select"
                    phx-value-id={s.id}
                    aria-pressed={to_string(@selected != nil and @selected.id == s.id)}
                    class="flex min-w-0 flex-[1_1_14rem] cursor-pointer flex-col text-left"
                  >
                    <span class="truncate font-semibold">
                      {s.enrollment.student.full_name}
                      <span class="font-normal text-base-content/70">
                        · {s.enrollment.class_group.label}
                      </span>
                    </span>
                    <span class="truncate text-sm text-base-content/75">{meta_cell(s)}</span>
                  </button>
                  <span class="flex shrink-0 items-center gap-2">
                    <span
                      :if={!s.parents_notified_on}
                      class="badge badge-sm border-warning/40 bg-warning/15 font-semibold text-warning"
                    >
                      {gettext("Famille à prévenir")}
                    </span>
                    <span
                      :if={s.parents_notified_on}
                      class="badge badge-sm border-primary/30 bg-primary/10 font-semibold text-primary"
                      title={date(s.parents_notified_on)}
                    >
                      {gettext("Famille prévenue")}
                    </span>
                    <a
                      :for={g <- List.wrap(guardian(s))}
                      id={"call-#{s.id}"}
                      href={"tel:#{g.phone_key}"}
                      class="btn btn-ghost btn-square btn-sm text-primary"
                      aria-label={
                        gettext("Appeler %{name} : %{phone}", name: g.full_name, phone: g.phone)
                      }
                      title={g.phone}
                    >
                      <.icon name="hero-phone" class="size-4" />
                    </a>
                    <button
                      :if={!s.parents_notified_on}
                      id={"notify-row-#{s.id}"}
                      type="button"
                      phx-click="notify"
                      phx-value-id={s.id}
                      class="btn btn-primary btn-sm whitespace-nowrap"
                    >
                      {gettext("Marquer notifié")}
                    </button>
                  </span>
                </li>
              </ul>
              <p :if={@page.results == []} class="p-4 text-sm text-base-content/70">
                {if @filters.notify,
                  do: gettext("Toutes les familles sont prévenues."),
                  else: gettext("Aucune sanction.")}
              </p>
              <nav
                :if={(@page.count || 0) > 50}
                id="sanctions-pager"
                class="join flex justify-center border-t border-base-300 p-2"
              >
                <.link
                  :for={p <- 1..div((@page.count || 0) + 49, 50)}
                  patch={page_link(@filters, p)}
                  class={["join-item btn btn-xs", p == @filters.page && "btn-active"]}
                >
                  {p}
                </.link>
              </nav>
            </div>
          </div>

          <div id="new-sanction" class="ta-panel flex flex-col gap-3 lg:sticky lg:top-4">
            <h2 class="text-[1.05rem] font-semibold">{gettext("Nouvelle sanction")}</h2>
            <form id="student-search" phx-change="search" class="flex flex-col gap-1.5">
              <label for="sanction-student" class="text-[0.8rem] font-semibold">
                {gettext("Élève")}
              </label>
              <input
                id="sanction-student"
                name="q"
                type="search"
                value={@q}
                placeholder={gettext("Nom ou matricule")}
                phx-debounce="300"
                autocomplete="off"
                class="input input-sm w-full"
              />
            </form>
            <div :if={@matches != []} class="flex flex-wrap gap-1.5">
              <button
                :for={e <- @matches}
                id={"pick-#{e.id}"}
                type="button"
                phx-click="pick"
                phx-value-id={e.id}
                class="btn btn-ghost btn-xs"
              >
                {e.student.full_name} · {e.class_group.label}
              </button>
            </div>
            <p
              :if={@entry.enrollment}
              id="picked-student"
              class="rounded-[0.4rem] bg-primary/10 px-2.5 py-1.5 text-sm font-semibold"
            >
              {@entry.enrollment.student.full_name} — {@entry.enrollment.class_group.label}
            </p>
            <div class="flex flex-col gap-1.5">
              <span class="text-[0.8rem] font-semibold">{gettext("Type")}</span>
              <div class="flex flex-wrap gap-1.5">
                <button
                  :for={t <- @types}
                  id={"type-#{t}"}
                  type="button"
                  phx-click="type"
                  phx-value-type={t}
                  aria-pressed={to_string(@entry.type == t)}
                  class={[
                    "min-h-9 rounded-full border px-3 text-[0.78rem] font-semibold transition-colors",
                    if(@entry.type == t,
                      do: "border-primary bg-primary/15 text-primary",
                      else: "border-base-300 hover:border-primary/60"
                    )
                  ]}
                >
                  {SanctionType.label(t)}
                </button>
              </div>
            </div>
            <form id="sanction-entry" phx-submit="add" class="flex flex-col gap-3">
              <div class="grid grid-cols-2 gap-2.5">
                <label class="flex flex-col gap-1.5">
                  <span class="text-[0.8rem] font-semibold">{gettext("Date")}</span>
                  <input
                    type="date"
                    name="entry[date]"
                    value={Date.to_iso8601(Reference.today())}
                    class="input input-sm ta-num w-full"
                  />
                </label>
                <label :if={@entry.type == :consigne} class="flex flex-col gap-1.5">
                  <span class="text-[0.8rem] font-semibold">{gettext("Durée (heures)")}</span>
                  <input
                    id="entry-hours"
                    type="number"
                    min="1"
                    max="40"
                    name="entry[duration_hours]"
                    class="input input-sm ta-num w-full"
                  />
                </label>
                <label :if={@entry.type == :exclusion_temporaire} class="flex flex-col gap-1.5">
                  <span class="text-[0.8rem] font-semibold">{gettext("Durée (jours)")}</span>
                  <input
                    id="entry-days"
                    type="number"
                    min="1"
                    name="entry[duration_days]"
                    class="input input-sm ta-num w-full"
                  />
                </label>
              </div>
              <label class="flex flex-col gap-1.5">
                <span class="text-[0.8rem] font-semibold">{gettext("Motif")}</span>
                <input
                  name="entry[reason]"
                  placeholder={gettext("Ex. bavardages répétés")}
                  class="input input-sm w-full"
                />
              </label>
              <p
                :if={type_note(@entry.type)}
                id="type-note"
                class="text-[0.78rem] text-base-content/80"
              >
                {type_note(@entry.type)}
              </p>
              <button type="submit" id="save-sanction" class="btn btn-primary w-full">
                {gettext("Enregistrer")}
              </button>
            </form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
