defmodule TeacherAssistantWeb.School.SanctionsLive do
  @moduledoc """
  SG → Sanctions (spec KLM4, L1; Vie scolaire redesign §2.4): a sticky
  « Nouvelle sanction » form (student, type, date, hours or days, reason) beside
  the year's sanctions with filters (class, type, parents to notify), an inline
  « Marquer notifiés », and a detail panel with the main guardian's phone.
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
         classes: Enrollment.list_class_groups(scope, scope.current_academic_year),
         types: Attendance.school_life_rules(scope).sanction_types_in_use,
         issuers: Map.new(Accounts.list_members(scope), &{&1.user_id, member_name(&1)}),
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

    assign(socket,
      page: page,
      selected: selected,
      families: Discipline.count_families_to_notify(scope, scope.current_academic_year)
    )
  end

  def handle_event("filter", params, socket) do
    query =
      %{"class" => params["class"], "type" => params["type"], "notify" => params["notify"]}
      |> Enum.reject(fn {_k, v} -> v in [nil, "", "false"] end)

    {:noreply, push_patch(socket, to: ~p"/school/sanctions?#{query}")}
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

  defp member_name(member), do: member.user && Accounts.User.display_name(member.user)
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

  defp page_link(filters, page) do
    query =
      %{
        "class" => filters.class,
        "type" => filters.type,
        "notify" => if(filters.notify, do: "1"),
        "page" => page
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    ~p"/school/sanctions?#{query}"
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
    [Calendar.strftime(s.date, "%d/%m"), s.reason]
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
            ngettext("%{count} famille à prévenir", "%{count} familles à prévenir", @families)
          }
        >
          <:actions>
            <.side_chip id="sanctions-count">
              {ngettext("%{count} sanction", "%{count} sanctions", @page.count || 0)}
            </.side_chip>
          </:actions>
        </.page_header>

        <div class="grid items-start gap-4 lg:grid-cols-[minmax(280px,360px)_minmax(0,1fr)]">
          <div
            id="new-sanction"
            class="ta-panel flex flex-col gap-3 lg:sticky lg:top-4"
          >
            <h2 class="text-[1.05rem] font-semibold">{gettext("Nouvelle sanction")}</h2>
            <form id="student-search" phx-change="search" class="flex flex-col gap-1.5">
              <label for="sanction-student" class="text-[0.8rem] font-semibold">
                {gettext("Élève")}
              </label>
              <input
                id="sanction-student"
                name="q"
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
                    "rounded-[0.45rem] border px-2.5 py-1.5 text-[0.78rem] font-semibold transition-colors",
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
                  placeholder={gettext("Bavardages répétés en Maths")}
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
              <button type="submit" id="save-sanction" class="btn btn-primary btn-sm w-full">
                {gettext("Enregistrer la sanction")}
              </button>
            </form>
          </div>

          <div class="flex min-w-0 flex-col gap-3">
            <form
              id="sanction-filters"
              phx-change="filter"
              class="flex flex-wrap items-center gap-2"
            >
              <select name="class" class="select select-sm w-auto">
                <option value="">{gettext("Toutes les classes")}</option>
                <option :for={c <- @classes} value={c.id} selected={c.id == @filters.class}>
                  {c.label}
                </option>
              </select>
              <select name="type" class="select select-sm w-auto">
                <option value="">{gettext("Tous les types")}</option>
                <option :for={t <- SanctionType.values()} value={t} selected={t == @filters.type}>
                  {SanctionType.label(t)}
                </option>
              </select>
              <label class="flex items-center gap-1.5 text-sm">
                <input
                  type="checkbox"
                  name="notify"
                  value="1"
                  checked={@filters.notify}
                  class="checkbox checkbox-sm"
                />
                {gettext("À notifier")}
              </label>
            </form>

            <aside
              :if={@selected}
              id="sanction-panel"
              class="ta-panel flex min-w-0 flex-col gap-2 !border-primary"
            >
              <.link
                navigate={~p"/school/students/#{@selected.enrollment.student_id}"}
                class="font-display text-lg font-semibold hover:text-primary"
              >
                {@selected.enrollment.student.full_name}
              </.link>
              <span class="text-sm">
                {@selected.enrollment.class_group.label} · {type_cell(@selected)} · {date(
                  @selected.date
                )}
              </span>
              <span :if={@selected.reason} class="text-sm">{@selected.reason}</span>
              <span :if={@issuers[@selected.issued_by_user_id]} class="text-xs text-base-content/70">
                {gettext("Par %{name}", name: @issuers[@selected.issued_by_user_id])}
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
                  {gettext("Marquer les parents notifiés")}
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

            <div class="min-w-0 overflow-x-auto rounded-box border border-base-300 bg-base-100">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Élève")}</th>
                    <th>{gettext("Type")}</th>
                    <th class="hidden sm:table-cell">{gettext("Date · motif")}</th>
                    <th>{gettext("Parents")}</th>
                  </tr>
                </thead>
                <tbody id="sanction-rows">
                  <tr
                    :for={s <- @page.results}
                    id={"sanction-#{s.id}"}
                    phx-click="select"
                    phx-value-id={s.id}
                    class={[
                      "cursor-pointer hover:bg-base-200/60",
                      @selected && @selected.id == s.id && "bg-primary/10"
                    ]}
                  >
                    <td>
                      <span class="flex flex-col">
                        <span class="font-semibold">{s.enrollment.student.full_name}</span>
                        <span class="text-[0.74rem] text-base-content/75">
                          {s.enrollment.class_group.label}
                        </span>
                      </span>
                    </td>
                    <td class="font-semibold">{type_cell(s)}</td>
                    <td class="hidden max-w-64 truncate text-[0.8rem] text-base-content/85 sm:table-cell">
                      {meta_cell(s)}
                    </td>
                    <td>
                      <span :if={s.parents_notified_on} class="text-[0.78rem] text-primary">
                        {gettext("Notifiés le %{date}",
                          date: Calendar.strftime(s.parents_notified_on, "%d/%m")
                        )}
                      </span>
                      <button
                        :if={!s.parents_notified_on}
                        id={"notify-row-#{s.id}"}
                        type="button"
                        phx-click="notify"
                        phx-value-id={s.id}
                        class="btn btn-outline btn-warning btn-xs whitespace-nowrap"
                      >
                        {gettext("Marquer notifiés")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@page.results == []} class="p-4 text-sm text-base-content/60">
                {gettext("Aucune sanction.")}
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
        </div>
      </section>
    </Layouts.app>
    """
  end
end
