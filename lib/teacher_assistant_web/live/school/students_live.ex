defmodule TeacherAssistantWeb.School.StudentsLive do
  @moduledoc """
  Censeur / SG → Élèves (spec KLM1, L3): the active year's students, searchable
  by name or matricule, filterable by class and by « sans contact parent »
  (Élèves redesign), with the main contact's phone.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_avatar: 1]

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.Sex
  alias TeacherAssistantWeb.School.EnrollDrawer

  @per_page 50

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
           classes: Enrollment.list_class_groups(scope, scope.current_academic_year),
           can_manage_classes?: Enrollment.can_manage_classes?(scope),
           can_manage_guardians?: Enrollment.can_manage_guardians?(scope),
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
    no_contact = params["no_contact"] == "1"
    offset = params |> Map.get("page", "1") |> parse_page() |> then(&((&1 - 1) * @per_page))
    list = &list_page(socket.assigns.current_scope, q, class_id, no_contact, &1)
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
     assign(socket, q: q, class_id: class_id, no_contact: no_contact, page: page, offset: offset)}
  end

  def handle_event("filter", %{"q" => q, "class" => class}, socket) do
    params = %{"q" => q, "class" => class, "no_contact" => socket.assigns.no_contact}
    {:noreply, push_patch(socket, to: list_path(params))}
  end

  def handle_event("open_enroll", _params, socket) when socket.assigns.can_manage_classes?,
    do: {:noreply, assign(socket, :drawer, :enroll)}

  def handle_event("open_enroll", _params, socket), do: {:noreply, socket}

  def handle_event("close_drawer", _params, socket), do: {:noreply, assign(socket, :drawer, nil)}

  def handle_event("toggle_no_contact", _params, socket) do
    %{q: q, class_id: class_id, no_contact: no_contact} = socket.assigns

    {:noreply,
     push_patch(socket,
       to: list_path(%{"q" => q, "class" => class_id, "no_contact" => not no_contact})
     )}
  end

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
    %{q: q, class_id: class_id, no_contact: no_contact, offset: offset} = socket.assigns
    scope = socket.assigns.current_scope

    socket
    |> assign_counts()
    |> assign(:page, list_page(scope, q, class_id, no_contact, offset))
  end

  defp list_page(scope, q, class_id, no_contact, offset) do
    Enrollment.list_school_students(scope, scope.current_academic_year,
      query: q,
      class_group_id: class_id,
      no_contact: no_contact,
      offset: offset
    )
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp list_path(params) do
    params =
      params
      |> Enum.map(fn
        {"no_contact", true} -> {"no_contact", "1"}
        {"no_contact", false} -> {"no_contact", nil}
        pair -> pair
      end)
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    ~p"/school/students?#{params}"
  end

  defp page_link(assigns, page),
    do:
      list_path(%{
        "q" => assigns.q,
        "class" => assigns.class_id,
        "no_contact" => assigns.no_contact,
        "page" => page
      })

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
            <p class="ta-eyebrow">{gettext("Établissement")}</p>
            <h1 class="mt-1.5 font-display text-2xl font-semibold leading-[1.1] sm:text-[2rem]">
              {gettext("Élèves")}
            </h1>
            <p id="students-subtitle" class="mt-2 text-[0.95rem] text-base-content/80">
              {ngettext(
                "%{count} inscrit en %{year}",
                "%{count} inscrits en %{year}",
                @counts.total,
                year: @current_scope.current_academic_year.name
              )} · {gettext("%{count} sans contact parent", count: @counts.no_contact)}
            </p>
          </div>
          <button
            :if={@can_manage_classes?}
            id="enroll-button"
            type="button"
            class="btn btn-primary btn-sm gap-1.5"
            phx-click="open_enroll"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Inscrire un élève")}
          </button>
        </header>

        <div class="flex flex-wrap items-center gap-2">
          <.form
            for={%{}}
            id="students-filter"
            phx-change="filter"
            phx-submit="filter"
            class="flex flex-wrap gap-2"
          >
            <label class="input input-sm w-full sm:w-72">
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
            <select name="class" class="select select-sm w-auto" aria-label={gettext("Classe")}>
              <option value="">{gettext("Toutes les classes")}</option>
              <option :for={c <- @classes} value={c.id} selected={c.id == @class_id}>
                {c.label}
              </option>
            </select>
          </.form>
          <button
            id="no-contact-chip"
            type="button"
            phx-click="toggle_no_contact"
            aria-pressed={to_string(@no_contact)}
            class={[
              "rounded-full border px-3 py-1 text-sm font-semibold transition-colors",
              if(@no_contact,
                do: "border-error/50 bg-error/15 text-error",
                else: "border-base-300 text-base-content/80 hover:text-base-content"
              )
            ]}
          >
            {gettext("Sans contact parent · %{count}", count: @counts.no_contact)}
          </button>
        </div>

        <div class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100">
          <div id="student-list" class="sm:hidden">
            <.list_row
              :for={e <- @page.results}
              id={"student-m-#{e.student.id}"}
              navigate={~p"/school/students/#{e.student.id}"}
              title={e.student.full_name}
              meta={
                case e.student.primary_guardian_link do
                  %{guardian: g} -> "#{e.class_group.label} · #{g.full_name}"
                  _ -> "#{e.class_group.label} · " <> gettext("Aucun contact")
                end
              }
              meta_class={!match?(%{guardian: _}, e.student.primary_guardian_link) && "!text-error"}
            >
              <:leading><.student_avatar student={e.student} class="size-10 text-xs" /></:leading>
              <:trailing>
                <span
                  :if={e.repeater}
                  class="rounded bg-warning/20 px-1.5 text-[0.7rem] font-semibold text-warning"
                >
                  {gettext("Redoublant")}
                </span>
              </:trailing>
            </.list_row>
          </div>
          <table class="table hidden sm:table">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th class="hidden sm:table-cell">{gettext("Matricule")}</th>
                <th>{gettext("Classe")}</th>
                <th>{gettext("Contact principal")}</th>
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
                      <span class="flex items-center gap-1.5 text-xs text-base-content/70">
                        {Sex.label(e.student.sex)}
                        <span
                          :if={e.repeater}
                          class="rounded bg-warning/20 px-1.5 text-[0.7rem] font-semibold text-warning"
                        >
                          {gettext("Redoublant")}
                        </span>
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
                      <span class="text-xs font-semibold text-error">{gettext("Aucun contact")}</span>
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
                patch={page_link(assigns, @current_page - 1)}
                class="btn btn-ghost btn-sm"
              >
                ← {gettext("Précédent")}
              </.link>
              <.link
                :if={@current_page < @last_page}
                id="students-next"
                patch={page_link(assigns, @current_page + 1)}
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
