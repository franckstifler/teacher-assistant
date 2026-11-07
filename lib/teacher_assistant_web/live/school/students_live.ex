defmodule TeacherAssistantWeb.School.StudentsLive do
  @moduledoc """
  Censeur / SG → Élèves (spec KLM1, L3; UX refonte 2026-11-03 « Élèves »): the
  active year's students, searchable by name or matricule, filterable by class
  (grouped by level), by « Redoublants » and « Sans photo », with the main
  contact's phone. A banner counts the parent contacts and leads to the students
  without one (`no_contact=1`) and to the class's import.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_avatar: 1]

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.Sex
  alias TeacherAssistantWeb.School.EnrollDrawer

  @per_page 50
  @flags [:no_contact, :repeater, :no_photo]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Enrollment.can_manage_register?(scope) ->
        leave(socket, gettext("La liste des élèves est réservée à l'administration."))

      is_nil(scope.current_academic_year) ->
        leave(socket, gettext("No active academic year"))

      true ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Élèves"),
           classes: Enrollment.list_class_groups(scope, scope.current_academic_year),
           can_manage_classes?: Enrollment.can_manage_classes?(scope),
           can_manage_guardians?: Enrollment.can_manage_guardians?(scope),
           exam_photos?: TeacherAssistant.Scope.module?(scope, :photos),
           drawer: nil
         )
         |> assign_counts()}
    end
  end

  defp leave(socket, message),
    do: {:ok, socket |> put_flash(:error, message) |> push_navigate(to: ~p"/school")}

  defp assign_counts(socket) do
    scope = socket.assigns.current_scope
    assign(socket, :counts, Enrollment.student_counts(scope, scope.current_academic_year))
  end

  def handle_params(params, _uri, socket) do
    q = params["q"] || ""
    class_id = Enum.find_value(socket.assigns.classes, &(&1.id == params["class"] && &1.id))
    filters = Map.new(@flags, &{&1, params[to_string(&1)] == "1"})
    offset = params |> Map.get("page", "1") |> parse_page() |> then(&((&1 - 1) * @per_page))
    list = &list_page(socket.assigns.current_scope, q, class_id, filters, &1)
    page = list.(offset)

    # A page past the end (stale link, hand-typed URL) shows the last one.
    {page, offset} =
      case page do
        %{results: [], count: count} when count > 0 and offset > 0 ->
          last = div(count - 1, @per_page) * @per_page
          {list.(last), last}

        _ ->
          {page, offset}
      end

    {:noreply,
     assign(socket, q: q, class_id: class_id, filters: filters, page: page, offset: offset)}
  end

  def handle_event("filter", %{"q" => q, "class" => class}, socket) do
    {:noreply,
     push_patch(socket, to: list_path(%{socket.assigns | q: q, class_id: class}, page: nil))}
  end

  def handle_event("open_enroll", _params, socket) when socket.assigns.can_manage_classes?,
    do: {:noreply, assign(socket, :drawer, :enroll)}

  def handle_event("open_enroll", _params, socket), do: {:noreply, socket}

  def handle_event("close_drawer", _params, socket), do: {:noreply, assign(socket, :drawer, nil)}

  def handle_info({EnrollDrawer, {:enrolled, cg, then}}, socket) do
    capacity = Enrollment.capacity(socket.assigns.current_scope, cg)

    {:noreply,
     socket
     |> put_flash(:info, EnrollDrawer.enrolled_message(cg, capacity))
     |> assign(:drawer, if(then == :another, do: :enroll, else: nil))
     |> refresh()}
  end

  def handle_info({EnrollDrawer, {:reenrolled, _cg}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Student re-enrolled."))
     |> assign(:drawer, nil)
     |> refresh()}
  end

  def handle_info({EnrollDrawer, :forbidden}, socket),
    do: {:noreply, Authz.put_not_allowed(socket)}

  # After an enrolment: the counts and the current page.
  defp refresh(socket) do
    %{q: q, class_id: class_id, filters: filters, offset: offset} = socket.assigns
    scope = socket.assigns.current_scope

    socket
    |> assign_counts()
    |> assign(:page, list_page(scope, q, class_id, filters, offset))
  end

  defp list_page(scope, q, class_id, filters, offset) do
    Enrollment.list_school_students(
      scope,
      scope.current_academic_year,
      [query: q, class_group_id: class_id, offset: offset] ++ Map.to_list(filters)
    )
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  # The list's URL for the current state, `changes` applied: `page: n`, or a
  # filter flag (`repeater: true`).
  defp list_path(assigns, changes) do
    filters = Map.merge(assigns.filters, Map.new(Keyword.delete(changes, :page)))

    params =
      [q: assigns.q, class: assigns.class_id, page: changes[:page]] ++
        for({flag, true} <- filters, do: {flag, "1"})

    ~p"/school/students?#{Enum.reject(params, fn {_k, v} -> v in [nil, ""] end)}"
  end

  defp class_label(classes, id), do: Enum.find_value(classes, &(&1.id == id && &1.label))

  defp repeater_label(:f), do: gettext("redoublante")
  defp repeater_label(_sex), do: gettext("redoublant")

  def render(assigns) do
    total = assigns.page.count || 0

    assigns =
      assign(assigns,
        current_page: div(assigns.offset, @per_page) + 1,
        last_page: max(div(total + @per_page - 1, @per_page), 1),
        total: total
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="students" class="flex flex-col gap-5">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p class="ta-eyebrow">{gettext("Scolarité")}</p>
            <h1 class="mt-1.5 font-display text-2xl font-semibold leading-[1.1] sm:text-[2rem]">
              {gettext("Élèves")}
            </h1>
            <p id="students-subtitle" class="ta-num mt-2 text-sm text-base-content/75">
              {@current_scope.current_academic_year.name} · {ngettext(
                "%{count} inscrit",
                "%{count} inscrits",
                @counts.total
              )}
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <%!-- Once a year (national exams): a page of Élèves, not a menu entry. --%>
            <.link
              :if={@exam_photos?}
              id="go-to-exam-photos"
              navigate={~p"/school/exam-photos"}
              class="btn btn-outline btn-sm gap-1.5"
            >
              <.icon name="hero-camera" class="size-4" /> {gettext("Photos d'examen")}
            </.link>
            <button
              :if={@can_manage_classes?}
              id="enroll-button"
              type="button"
              class="btn btn-primary btn-sm gap-1.5"
              phx-click="open_enroll"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Inscrire un élève")}
            </button>
          </div>
        </header>

        <section
          :if={@counts.no_contact > 0 or @filters.no_contact}
          id="contacts-banner"
          aria-label={gettext("Contacts parents")}
          class="flex flex-wrap items-center gap-3 rounded-box border border-warning/40 bg-base-100 px-4 py-3.5 sm:px-5"
        >
          <div class="min-w-64 flex-1">
            <p class="text-[0.95rem] font-semibold">
              {gettext("Contacts parents : %{with} sur %{total}",
                with: @counts.total - @counts.no_contact,
                total: @counts.total
              )}
            </p>
            <p class="mt-0.5 text-sm text-base-content/70">
              {gettext("Ils servent aux avis d'absence, de sanction et de frais.")}
            </p>
          </div>
          <.link
            id="no-contact-link"
            patch={list_path(assigns, no_contact: not @filters.no_contact, page: nil)}
            aria-pressed={to_string(@filters.no_contact)}
            class={["btn btn-sm", if(@filters.no_contact, do: "btn-outline", else: "btn-warning")]}
          >
            {if @filters.no_contact,
              do: gettext("Voir tous les élèves"),
              else:
                ngettext(
                  "Voir l'élève sans contact",
                  "Voir les %{count} élèves sans contact",
                  @counts.no_contact
                )}
          </.link>
          <.link
            :if={@can_manage_classes? && @class_id}
            id="import-contacts-link"
            navigate={~p"/school/classes/#{@class_id}/import"}
            class="btn btn-outline btn-sm"
          >
            {gettext("Importer la liste de %{class}", class: class_label(@classes, @class_id))}
          </.link>
          <span
            :if={@can_manage_classes? && !@class_id}
            id="import-contacts-hint"
            class="text-xs text-base-content/70"
          >
            {gettext("Choisissez une classe pour importer sa liste.")}
          </span>
        </section>

        <div class="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center">
          <.form
            for={%{}}
            id="students-filter"
            phx-change="filter"
            phx-submit="filter"
            class="flex flex-wrap gap-2 sm:flex-1"
          >
            <label class="input min-w-0 flex-[2_1_16rem]">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="search"
                name="q"
                value={@q}
                placeholder={gettext("Nom ou matricule")}
                aria-label={gettext("Nom ou matricule")}
                phx-debounce="300"
              />
            </label>
            <.class_picker
              id="students-class"
              classes={@classes}
              current={@class_id}
              stepper={false}
              select_class={nil}
              prompt={gettext("Toutes les classes")}
              class="min-w-0 flex-[1_1_11rem]"
            />
          </.form>
          <.filter_pills id="student-filters" label={gettext("Filtrer les élèves")}>
            <:pill
              id="repeater-pill"
              patch={list_path(assigns, repeater: not @filters.repeater, page: nil)}
              count={@counts.repeater}
              current={@filters.repeater}
            >
              {gettext("Redoublants")}
            </:pill>
            <:pill
              id="no-photo-pill"
              patch={list_path(assigns, no_photo: not @filters.no_photo, page: nil)}
              count={@counts.no_photo}
              current={@filters.no_photo}
            >
              {gettext("Sans photo")}
            </:pill>
          </.filter_pills>
        </div>

        <div class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100">
          <div id="student-list" class="sm:hidden">
            <.list_row
              :for={e <- @page.results}
              id={"student-m-#{e.student.id}"}
              navigate={~p"/school/students/#{e.student.id}"}
              title={e.student.full_name}
              meta={
                Enum.join(
                  [
                    e.class_group.label,
                    e.repeater && repeater_label(e.student.sex),
                    case e.student.primary_guardian_link do
                      %{guardian: g} -> g.full_name
                      _ -> gettext("sans contact")
                    end
                  ]
                  |> Enum.filter(& &1),
                  " · "
                )
              }
            >
              <:leading><.student_avatar student={e.student} class="size-10 text-xs" /></:leading>
            </.list_row>
          </div>
          <table class="table max-sm:hidden">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th class="hidden sm:table-cell">{gettext("Matricule")}</th>
                <th>{gettext("Classe")}</th>
                <th>{gettext("Contact parent")}</th>
              </tr>
            </thead>
            <tbody id="student-rows">
              <tr
                :for={e <- @page.results}
                id={"student-#{e.student.id}"}
                phx-click={JS.navigate(~p"/school/students/#{e.student.id}")}
                class="cursor-pointer transition-colors hover:bg-base-200/60"
              >
                <td>
                  <span class="flex items-center gap-3">
                    <.student_avatar student={e.student} />
                    <span class="min-w-0">
                      <.link
                        navigate={~p"/school/students/#{e.student.id}"}
                        class="block font-semibold hover:text-primary"
                      >
                        {e.student.full_name}
                      </.link>
                      <span class="block text-xs text-base-content/70">
                        {Sex.label(e.student.sex)}<span :if={e.repeater}> · {repeater_label(
                          e.student.sex
                        )}</span>
                      </span>
                    </span>
                  </span>
                </td>
                <td class="ta-num hidden text-sm sm:table-cell">{e.student.matricule || "—"}</td>
                <td>
                  <span class="inline-flex rounded-[0.4rem] border border-base-300 px-2 py-0.5 text-xs font-semibold">
                    {e.class_group.label}
                  </span>
                </td>
                <td class="text-sm">
                  <%= case e.student.primary_guardian_link do %>
                    <% %{guardian: g} -> %>
                      <span>{g.full_name}</span>
                      <span class="text-base-content/70">·</span>
                      <a href={"tel:#{g.phone_key}"} class="ta-num link link-hover">{g.phone}</a>
                    <% _ -> %>
                      <.link
                        :if={@can_manage_guardians?}
                        id={"add-contact-#{e.student.id}"}
                        navigate={~p"/school/students/#{e.student.id}"}
                        class="text-sm font-semibold text-primary"
                      >
                        {gettext("+ Ajouter")}
                      </.link>
                      <span :if={!@can_manage_guardians?} class="text-base-content/60">—</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@page.results == []} id="students-empty" class="p-4 text-sm text-base-content/70">
            {gettext("Aucun élève ne correspond.")}
          </p>
          <div
            :if={@total > 0}
            class="flex flex-wrap items-center justify-between gap-2 border-t border-base-300 px-4 py-2.5 text-sm"
          >
            <span id="students-range" class="ta-num text-base-content/70">
              {gettext("%{first}–%{last} sur %{total}",
                first: @offset + 1,
                last: @offset + length(@page.results),
                total: @total
              )}
            </span>
            <span :if={@last_page > 1} class="flex gap-1">
              <.link
                :if={@current_page > 1}
                id="students-prev"
                patch={list_path(assigns, page: @current_page - 1)}
                class="btn btn-ghost btn-sm"
              >
                ← {gettext("Précédent")}
              </.link>
              <.link
                :if={@current_page < @last_page}
                id="students-next"
                patch={list_path(assigns, page: @current_page + 1)}
                class="btn btn-ghost btn-sm"
              >
                {gettext("Suivant")} →
              </.link>
            </span>
          </div>
        </div>
      </section>

      <.live_component
        :if={@drawer == :enroll}
        module={EnrollDrawer}
        id="enroll"
        scope={@current_scope}
        can_manage_guardians?={@can_manage_guardians?}
      />
    </Layouts.app>
    """
  end
end
