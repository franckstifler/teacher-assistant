defmodule TeacherAssistantWeb.School.StudentsLive do
  @moduledoc """
  Censeur / SG → Élèves (spec KLM1, L3): the active year's students, searchable
  by name or matricule, filterable by class, with the main contact's phone.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.GuardianRelationship

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Enrollment.can_manage_register?(scope) do
      {:ok,
       assign(socket,
         classes: Enrollment.list_class_groups(scope, scope.current_academic_year)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La liste des élèves est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    q = params["q"] || ""
    class_id = Enum.find_value(socket.assigns.classes, &(&1.id == params["class"] && &1.id))
    offset = params |> Map.get("page", "1") |> parse_page() |> then(&((&1 - 1) * 50))

    page =
      Enrollment.list_school_students(
        socket.assigns.current_scope,
        socket.assigns.current_scope.current_academic_year,
        query: q,
        class_group_id: class_id,
        offset: offset
      )

    {:noreply, assign(socket, q: q, class_id: class_id, page: page, offset: offset)}
  end

  def handle_event("filter", %{"q" => q, "class" => class}, socket) do
    params = %{"q" => q, "class" => class} |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()
    {:noreply, push_patch(socket, to: ~p"/school/students?#{params}")}
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp page_link(assigns, page) do
    params =
      %{"q" => assigns.q, "class" => assigns.class_id, "page" => page}
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    ~p"/school/students?#{params}"
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        current_page: div(assigns.offset, 50) + 1,
        last_page: max(div((assigns.page.count || 0) + 49, 50), 1)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="students" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("École")} title={gettext("Élèves")}>
          <:actions>
            <.side_chip id="students-count">
              {ngettext("%{count} élève", "%{count} élèves", @page.count || 0)}
            </.side_chip>
          </:actions>
        </.page_header>

        <.form
          for={%{}}
          id="students-filter"
          phx-change="filter"
          phx-submit="filter"
          class="flex flex-wrap gap-2"
        >
          <input
            type="search"
            name="q"
            value={@q}
            placeholder={gettext("Nom ou matricule")}
            phx-debounce="300"
            class="input input-sm w-full sm:w-72"
          />
          <select name="class" class="select select-sm">
            <option value="">{gettext("Toutes les classes")}</option>
            <option :for={c <- @classes} value={c.id} selected={c.id == @class_id}>{c.label}</option>
          </select>
        </.form>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Classe")}</th>
                <th>{gettext("Sexe")}</th>
                <th>{gettext("Contact principal")}</th>
              </tr>
            </thead>
            <tbody id="student-rows">
              <tr
                :for={e <- @page.results}
                id={"student-#{e.student.id}"}
                class="hover:bg-base-200/60"
              >
                <td>
                  <.link
                    navigate={~p"/school/students/#{e.student.id}"}
                    class="font-semibold hover:text-primary"
                  >
                    {e.student.full_name}
                  </.link>
                </td>
                <td class="font-mono text-xs">{e.student.matricule || "—"}</td>
                <td>{e.class_group.label}</td>
                <td>{TeacherAssistant.Academics.Sex.label(e.student.sex)}</td>
                <td>
                  <%= case e.student.primary_guardian_link do %>
                    <% %{guardian: g} -> %>
                      <span>{g.full_name}</span>
                      <span class="text-base-content/60">· {GuardianRelationship.label(g.relationship)}</span>
                      <a href={"tel:#{g.phone_key}"} class="link link-primary ml-1 font-mono text-xs">{g.phone}</a>
                    <% _ -> %>
                      <span class="text-base-content/50">—</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@page.results == []} id="students-empty" class="p-4 text-sm text-base-content/60">
            {gettext("Aucun élève ne correspond.")}
          </p>
        </div>

        <nav :if={@last_page > 1} class="join self-center">
          <.link
            :for={p <- 1..@last_page}
            patch={page_link(assigns, p)}
            class={["join-item btn btn-sm", p == @current_page && "btn-active"]}
          >
            {p}
          </.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end
end
