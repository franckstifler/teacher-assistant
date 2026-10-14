defmodule TeacherAssistantWeb.School.AssignmentsLive do
  @moduledoc """
  Settings → Affectations (spec J2, T04): the school's classes × subjects grid with
  each class's form master, a side panel to assign, reassign or remove (showing each
  teacher's load after the change), the teachers' loads, and the statutory service.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.AssignmentGrid

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Curriculum.can_manage_assignments?(scope) do
      {:ok, socket |> assign(selected: nil, pp_for: nil, hours: "4", panel_error: nil) |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket) do
    grid = Curriculum.assignment_overview(socket.assigns.current_scope)
    users = Map.new(grid.members, &{&1.user_id, &1.user})
    assign(socket, grid: grid, users: users)
  end

  # --- events ---------------------------------------------------------------

  def handle_event("select", %{"class" => cg_id, "subject" => s_id}, socket) do
    cell = socket.assigns.grid.cells[{cg_id, s_id}]

    if cell && cell.kind in [:assigned, :to_assign] do
      hours = if cell.kind == :assigned, do: to_string(cell.tc.weekly_hours || 4), else: "4"

      {:noreply,
       assign(socket, selected: {cg_id, s_id}, pp_for: nil, hours: hours, panel_error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hours", %{"hours" => hours}, socket),
    do: {:noreply, assign(socket, hours: hours)}

  def handle_event("pick", %{"user" => user_id}, socket) do
    with {cg_id, s_id} <- socket.assigns.selected,
         %{} = cg <- Enum.find(socket.assigns.grid.classes, &(&1.id == cg_id)),
         %{} = subject <- Enum.find(socket.assigns.grid.subjects, &(&1.id == s_id)) do
      socket.assigns.current_scope
      |> Curriculum.place_assignment(cg, subject, user_id, socket.assigns.hours)
      |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove", _params, socket) do
    with {cg_id, s_id} <- socket.assigns.selected,
         %{kind: :assigned, tc: tc} <- socket.assigns.grid.cells[{cg_id, s_id}] do
      case Curriculum.remove_assignment(socket.assigns.current_scope, tc) do
        :ok -> {:noreply, socket |> assign(selected: nil) |> load()}
        other -> after_write(other, socket)
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pp", %{"class" => cg_id}, socket),
    do: {:noreply, assign(socket, pp_for: cg_id, selected: nil, panel_error: nil)}

  def handle_event("pp_pick", %{"user" => user_id}, socket) do
    with cg_id when is_binary(cg_id) <- socket.assigns.pp_for,
         %{} = cg <- Enum.find(socket.assigns.grid.classes, &(&1.id == cg_id)) do
      user_id = if user_id == "", do: nil, else: user_id

      socket.assigns.current_scope
      |> Enrollment.set_form_master(cg, user_id)
      |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("service", %{"service" => value}, socket) do
    case Accounts.update_school_service(socket.assigns.current_scope, value) do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("Indiquez un nombre d'heures entre 1 et 40."))}
    end
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, selected: nil, pp_for: nil, panel_error: nil)}

  defp after_write({:ok, _}, socket), do: {:noreply, socket |> assign(panel_error: nil) |> load()}

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, reason}, socket),
    do: {:noreply, assign(socket, panel_error: error_text(reason))}

  defp error_text(:has_data), do: gettext("Impossible : des notes ou une progression existent.")
  defp error_text(:invalid_hours), do: gettext("Indiquez des heures entre 1 et 40.")
  defp error_text(:not_assignable), do: gettext("Cette personne n'est pas membre de l'école.")

  defp error_text(:combined),
    do: gettext("Cours regroupé : modifiez-le depuis la fiche de la classe.")

  defp error_text(_), do: gettext("Modification non enregistrée.")

  # --- view helpers -----------------------------------------------------------

  defp name(users, id) do
    case users[id] do
      nil -> "—"
      u -> Accounts.User.display_name(u)
    end
  end

  # Members for the panel: those teaching the subject somewhere first.
  defp candidates(grid, subject_id) do
    teaching =
      grid.cells
      |> Enum.filter(fn {{_c, s}, cell} -> s == subject_id and cell.kind == :assigned end)
      |> MapSet.new(fn {_, cell} -> cell.teacher_id end)

    Enum.sort_by(
      grid.members,
      &{not MapSet.member?(teaching, &1.user_id),
       String.downcase(Accounts.User.display_name(&1.user))}
    )
  end

  defp old_hours(%{kind: :assigned, tc: tc}), do: tc.weekly_hours || 0
  defp old_hours(_cell), do: 0

  defp hours_int(hours) do
    case Integer.parse(hours || "") do
      {n, _} -> n
      _ -> 0
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="assignments" class="space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Affectations")}
          subtitle={
            gettext(
              "Qui enseigne quoi, dans quelle classe — avec la charge horaire de chaque enseignant."
            )
          }
        />

        <div class="flex flex-wrap gap-3 text-sm">
          <span
            id="to-assign-count"
            class={if @grid.to_assign > 0, do: "text-error font-semibold", else: "text-success"}
          >
            {if @grid.to_assign > 0,
              do:
                ngettext(
                  "%{count} enseignement à affecter",
                  "%{count} enseignements à affecter",
                  @grid.to_assign
                ),
              else: gettext("Tous les enseignements sont affectés")}
          </span>
          <span :if={@grid.without_pp > 0} class="text-warning font-semibold">
            {ngettext(
              "%{count} classe sans professeur principal",
              "%{count} classes sans professeur principal",
              @grid.without_pp
            )}
          </span>
        </div>

        <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_320px]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="assignments-grid" class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Classe")}</th>
                  <th>{gettext("Prof. principal")}</th>
                  <th :for={s <- @grid.subjects} class="whitespace-nowrap">{s.name}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @grid.classes}>
                  <td class="font-semibold whitespace-nowrap">{c.label}</td>
                  <td>
                    <button
                      id={"pp-#{c.id}"}
                      type="button"
                      phx-click="pp"
                      phx-value-class={c.id}
                      class={["text-left text-xs", is_nil(c.form_master_user_id) && "text-warning"]}
                    >
                      {if c.form_master_user_id,
                        do: name(@users, c.form_master_user_id),
                        else: gettext("Sans professeur principal")}
                    </button>
                  </td>
                  <td :for={s <- @grid.subjects} class="p-1">
                    <% cell = @grid.cells[{c.id, s.id}] %>
                    <%= case cell.kind do %>
                      <% :not_taught -> %>
                        <div
                          id={"cell-#{c.id}-#{s.id}"}
                          class="h-9 rounded border border-dashed border-base-300"
                          title={gettext("Non enseignée")}
                        >
                        </div>
                      <% :to_assign -> %>
                        <button
                          id={"cell-#{c.id}-#{s.id}"}
                          type="button"
                          phx-click="select"
                          phx-value-class={c.id}
                          phx-value-subject={s.id}
                          class={[
                            "h-9 w-full rounded bg-error/30 px-2 text-xs",
                            @selected == {c.id, s.id} && "ring-2 ring-base-content"
                          ]}
                        >
                          {gettext("À affecter")}
                        </button>
                      <% :assigned -> %>
                        <button
                          id={"cell-#{c.id}-#{s.id}"}
                          type="button"
                          phx-click="select"
                          phx-value-class={c.id}
                          phx-value-subject={s.id}
                          class={[
                            "h-9 w-full truncate rounded px-2 text-xs",
                            if(cell.over?, do: "bg-warning/30", else: "bg-primary/15"),
                            @selected == {c.id, s.id} && "ring-2 ring-base-content"
                          ]}
                        >
                          {name(@users, cell.teacher_id)}
                          <span :if={cell.combined?} class="badge badge-ghost badge-xs">{gettext(
                            "regroupé"
                          )}</span>
                        </button>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside class="space-y-4">
            <%= if @selected do %>
              <% {cg_id, s_id} = @selected %>
              <% cell = @grid.cells[{cg_id, s_id}] %>
              <% cls = Enum.find(@grid.classes, &(&1.id == cg_id)) %>
              <% subj = Enum.find(@grid.subjects, &(&1.id == s_id)) %>
              <% current = if cell.kind == :assigned, do: cell.teacher_id %>
              <div id="assign-panel" class="ta-panel space-y-3 p-4">
                <div class="flex items-start justify-between gap-2">
                  <h2 class="font-semibold">{cls.label} · {subj.name}</h2>
                  <button
                    type="button"
                    phx-click="close"
                    class="btn btn-ghost btn-xs"
                    aria-label={gettext("Fermer")}
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <%= if cell.kind == :assigned and cell.combined? do %>
                  <p class="text-sm">
                    {gettext("Cours regroupé : modifiez-le depuis la fiche de la classe.")}
                  </p>
                  <.link navigate={~p"/school/classes/#{cg_id}"} class="link link-primary text-sm">{gettext(
                    "Ouvrir la classe"
                  )}</.link>
                <% else %>
                  <p class="text-sm text-base-content/70">
                    {if current,
                      do: gettext("Affecté à %{name}", name: name(@users, current)),
                      else: gettext("Non affecté")}
                  </p>
                  <.form for={%{}} id="hours-form" phx-change="hours">
                    <.input
                      name="hours"
                      value={@hours}
                      inputmode="numeric"
                      label={gettext("Heures / semaine")}
                      class="input input-sm w-20 text-right"
                    />
                  </.form>
                  <ul class="space-y-1">
                    <li :for={m <- candidates(@grid, s_id)}>
                      <% after_load =
                        AssignmentGrid.load_after(
                          @grid,
                          m.user_id,
                          hours_int(@hours),
                          current,
                          old_hours(cell)
                        ) %>
                      <% service = AssignmentGrid.service(@grid, m.user_id) %>
                      <button
                        id={"pick-#{m.user_id}"}
                        type="button"
                        phx-click="pick"
                        phx-value-user={m.user_id}
                        class={[
                          "flex w-full justify-between rounded border px-2 py-1 text-left text-sm",
                          m.user_id == current && "border-primary bg-primary/10"
                        ]}
                      >
                        <span class="truncate">{name(@users, m.user_id)}</span>
                        <span class={["ta-num text-xs", after_load > service && "text-error"]}>
                          {if m.user_id == current,
                            do:
                              gettext("%{load} h / %{service} h", load: after_load, service: service),
                            else:
                              gettext("%{load} h / %{service} h après",
                                load: after_load,
                                service: service
                              )}
                        </span>
                      </button>
                    </li>
                  </ul>
                  <button
                    :if={current}
                    id="remove-assignment"
                    type="button"
                    phx-click="remove"
                    class="btn btn-ghost btn-sm text-error"
                  >
                    {gettext("Retirer l'affectation")}
                  </button>
                <% end %>
                <p :if={@panel_error} id="panel-error" class="text-sm text-error">{@panel_error}</p>
              </div>
            <% end %>

            <%= if @pp_for do %>
              <% cls = Enum.find(@grid.classes, &(&1.id == @pp_for)) %>
              <div id="pp-panel" class="ta-panel space-y-3 p-4">
                <h2 class="font-semibold">
                  {gettext("Professeur principal · %{class}", class: cls.label)}
                </h2>
                <ul class="space-y-1">
                  <li :for={m <- @grid.members}>
                    <button
                      id={"pp-pick-#{m.user_id}"}
                      type="button"
                      phx-click="pp_pick"
                      phx-value-user={m.user_id}
                      class={[
                        "w-full rounded border px-2 py-1 text-left text-sm",
                        cls.form_master_user_id == m.user_id && "border-primary bg-primary/10"
                      ]}
                    >
                      {name(@users, m.user_id)}
                    </button>
                  </li>
                </ul>
                <button
                  id="pp-none"
                  type="button"
                  phx-click="pp_pick"
                  phx-value-user=""
                  class="btn btn-ghost btn-sm"
                >{gettext("Aucun")}</button>
                <p :if={@panel_error} id="panel-error" class="text-sm text-error">{@panel_error}</p>
              </div>
            <% end %>

            <div id="loads" class="ta-panel space-y-2 p-4">
              <h2 class="ta-eyebrow">{gettext("Charge des enseignants")}</h2>
              <div
                :for={{id, l} <- Enum.sort_by(@grid.loads, fn {_, l} -> -l.load end)}
                id={"load-#{id}"}
                class="space-y-1"
              >
                <div class="flex justify-between text-sm">
                  <span class="truncate">{name(@users, id)}</span>
                  <span class={["ta-num", l.over? && "text-error"]}>{l.load} h / {l.service} h</span>
                </div>
                <div class="h-1.5 rounded bg-base-200">
                  <div
                    class={["h-1.5 rounded", if(l.over?, do: "bg-error", else: "bg-primary")]}
                    style={"width: #{min(100, round(l.load / max(l.service, 1) * 100))}%"}
                  >
                  </div>
                </div>
              </div>
            </div>

            <.form
              for={%{}}
              id="service-form"
              phx-submit="service"
              class="ta-panel flex items-end gap-2 p-4"
            >
              <.input
                name="service"
                value={@grid.school_hours}
                inputmode="numeric"
                label={gettext("Service statutaire (h / semaine)")}
                class="input input-sm w-20 text-right"
              />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            </.form>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
