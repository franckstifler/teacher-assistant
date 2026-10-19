defmodule TeacherAssistantWeb.School.RoomsLive do
  @moduledoc """
  Settings → Salles (spec J3, T02): the school's rooms (name, kind, capacity), add /
  edit / deactivate, delete while unused; and each class's home room for the active
  year. Admin axis (Proviseur, Censeur).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.{RoomKind, SchoolTemplates}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Timetabling.can_edit_timetable?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      {:ok, socket |> assign(year: year, editing: nil, error: nil) |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    rooms = Organization.list_rooms(scope)

    classes =
      scope
      |> Enrollment.list_class_groups(socket.assigns.year)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

    assign(socket,
      rooms: rooms,
      in_use: MapSet.new(for r <- rooms, Organization.room_in_use?(scope, r), do: r.id),
      classes: classes
    )
  end

  def handle_event("save_room", %{"room" => params}, socket) do
    attrs = %{
      name: params["name"],
      kind: params["kind"],
      capacity: blank_to_nil(params["capacity"])
    }

    result =
      case socket.assigns.editing do
        nil -> Organization.create_room(socket.assigns.current_scope, attrs)
        room -> Organization.update_room(socket.assigns.current_scope, room, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing: nil, error: nil)
         |> load()
         |> put_flash(:info, gettext("Salle enregistrée."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error: gettext("Vérifiez le nom (unique) et la capacité (au moins 1 place).")
         )}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, assign(socket, editing: find_room(socket, id), error: nil)}

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing: nil, error: nil)}

  def handle_event("toggle_active", %{"id" => id}, socket) do
    with %{} = room <- find_room(socket, id) do
      socket.assigns.current_scope
      |> Organization.update_room(room, %{active?: not room.active?})
      |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %{} = room <- find_room(socket, id) do
      socket.assigns.current_scope |> Organization.delete_room(room) |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_home_room", %{"class_id" => class_id} = params, socket) do
    room_id = blank_to_nil(params["room_id"])

    with %{} = cg <- Enum.find(socket.assigns.classes, &(&1.id == class_id)),
         true <-
           is_nil(room_id) or Enum.any?(socket.assigns.rooms, &(&1.id == room_id and &1.active?)) do
      socket.assigns.current_scope |> Enrollment.set_home_room(cg, room_id) |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  defp after_write(result, socket) when result == :ok or elem(result, 0) == :ok,
    do: {:noreply, load(socket)}

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, :in_use}, socket),
    do:
      {:noreply,
       socket |> put_flash(:error, gettext("Cette salle est utilisée : désactivez-la.")) |> load()}

  defp after_write({:error, _}, socket),
    do:
      {:noreply, socket |> put_flash(:error, gettext("Modification non enregistrée.")) |> load()}

  defp find_room(socket, id), do: Enum.find(socket.assigns.rooms, &(&1.id == id))

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v

  defp kind_options, do: Enum.map(RoomKind.values(), &{RoomKind.label(&1), &1})

  # Active rooms for a class's select; a room already home to other classes says which.
  defp home_room_options(rooms, classes, cg) do
    for r <- rooms, r.active? or r.id == cg.home_room_id do
      others =
        classes
        |> Enum.filter(&(&1.home_room_id == r.id and &1.id != cg.id))
        |> Enum.map_join(", ", & &1.label)

      label =
        if others == "",
          do: r.name,
          else: gettext("%{room} (déjà : %{classes})", room: r.name, classes: others)

      {label, r.id}
    end
  end

  defp field(nil, :kind), do: "classroom"
  defp field(nil, _key), do: ""
  defp field(room, :kind), do: to_string(room.kind)
  defp field(room, :capacity), do: room.capacity && to_string(room.capacity)
  defp field(room, key), do: Map.fetch!(room, key)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="rooms" class="space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Salles")}
          subtitle={gettext("Salles de classe, laboratoires, salle informatique, ateliers.")}
        />

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table :if={@rooms != []} id="rooms-table" class="table">
            <thead>
              <tr>
                <th>{gettext("Salle")}</th>
                <th>{gettext("Type")}</th>
                <th class="text-right">{gettext("Places")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @rooms} id={"room-#{r.id}"} class={!r.active? && "opacity-60"}>
                <td class="font-semibold">
                  {r.name}
                  <span :if={!r.active?} class="badge badge-ghost badge-sm ml-1">
                    {pgettext("room", "Inactive")}
                  </span>
                </td>
                <td>{RoomKind.label(r.kind)}</td>
                <td class="ta-num text-right">{r.capacity || "—"}</td>
                <td class="whitespace-nowrap text-right">
                  <button
                    id={"edit-room-#{r.id}"}
                    type="button"
                    phx-click="edit"
                    phx-value-id={r.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Modifier")}
                  </button>
                  <button
                    id={"deactivate-room-#{r.id}"}
                    type="button"
                    phx-click="toggle_active"
                    phx-value-id={r.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {if r.active?, do: gettext("Désactiver"), else: gettext("Réactiver")}
                  </button>
                  <button
                    :if={not MapSet.member?(@in_use, r.id)}
                    id={"delete-room-#{r.id}"}
                    type="button"
                    phx-click="delete"
                    phx-value-id={r.id}
                    data-confirm={gettext("Supprimer cette salle ?")}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    {gettext("Supprimer")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@rooms == []} id="rooms-empty" class="p-4 text-sm text-base-content/70">
            {gettext("Aucune salle pour l'instant.")}
          </p>
        </div>

        <.form
          for={%{}}
          as={:room}
          id="room-form"
          phx-submit="save_room"
          class="grid items-end gap-2 rounded-box border border-base-300 bg-base-100 p-4 sm:grid-cols-4"
        >
          <.input name="room[name]" value={field(@editing, :name)} label={gettext("Nom")} />
          <.input
            name="room[kind]"
            type="select"
            value={field(@editing, :kind)}
            options={kind_options()}
            label={gettext("Type")}
          />
          <.input
            name="room[capacity]"
            type="number"
            min="1"
            value={field(@editing, :capacity)}
            label={gettext("Places (facultatif)")}
          />
          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm">
              {if @editing, do: gettext("Enregistrer"), else: gettext("Ajouter")}
            </button>
            <button
              :if={@editing}
              id="cancel-edit"
              type="button"
              phx-click="cancel_edit"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Annuler")}
            </button>
          </div>
          <p :if={@error} id="room-error" class="text-sm text-error sm:col-span-4">{@error}</p>
        </.form>

        <section id="home-rooms" class="space-y-2">
          <h2 class="ta-eyebrow">{gettext("Salles des classes")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext("La salle où la classe a cours, sauf quand un cours a sa propre salle.")}
          </p>
          <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
            <.form
              :for={c <- @classes}
              for={%{}}
              id={"home-room-#{c.id}"}
              phx-change="set_home_room"
              class="flex items-center justify-between gap-3 px-4 py-2"
            >
              <input type="hidden" name="class_id" value={c.id} />
              <span class="font-semibold">{c.label}</span>
              <select name="room_id" class="select select-sm w-56">
                <option value="">—</option>
                <option
                  :for={{label, id} <- home_room_options(@rooms, @classes, c)}
                  value={id}
                  selected={id == c.home_room_id}
                >
                  {label}
                </option>
              </select>
            </.form>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
