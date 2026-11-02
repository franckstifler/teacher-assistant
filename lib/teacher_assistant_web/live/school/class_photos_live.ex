defmodule TeacherAssistantWeb.School.ClassPhotosLive do
  @moduledoc "Spec 2026-10-12 §7: a class's photos — grid, per-student sheet, chained séance."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistantWeb.Authz
  import TeacherAssistantWeb.StudentPhotoComponents

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Enrollment.can_manage_register?(scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id) do
      {:ok,
       socket
       |> assign(
         page_title: "#{cg.label} · #{gettext("Photos")}",
         cg: cg,
         only_missing?: false,
         sheet: nil,
         confirm_remove?: false,
         redo_all?: false
       )
       |> assign(roster: Enrollment.list_roster(scope, cg))
       |> assign_queue()
       |> allow_photo_upload(&handle_progress/3)}
    else
      _ -> {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_event("validate_photo", _params, socket),
    do: {:noreply, drop_refused_entries(socket)}

  def handle_event("photo_unreadable", _params, socket),
    do: {:noreply, put_flash(socket, :error, unreadable_message())}

  def handle_event("toggle_missing", _params, socket),
    do: {:noreply, update(socket, :only_missing?, &(!&1))}

  def handle_event("open_sheet", %{"id" => id}, socket),
    do: {:noreply, assign(socket, sheet: id, confirm_remove?: false)}

  def handle_event("close_sheet", _params, socket),
    do: {:noreply, assign(socket, sheet: nil, confirm_remove?: false)}

  def handle_event("ask_remove", _params, socket),
    do: {:noreply, assign(socket, confirm_remove?: true)}

  def handle_event("toggle_redo_all", _params, socket),
    do: {:noreply, socket |> update(:redo_all?, &(!&1)) |> assign_queue()}

  def handle_event("remove_photo", _params, socket) do
    with %{student: student} <- row(socket, socket.assigns.sheet),
         {:ok, updated} <- remove_photo(socket, student) do
      {:noreply, socket |> replace_student(updated) |> assign(sheet: nil, confirm_remove?: false)}
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
      nil -> {:noreply, assign(socket, sheet: nil, confirm_remove?: false)}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photo, ref)}

  defp handle_progress(:photo, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_progress(:photo, entry, socket) do
    student_id = entry_student_id(entry)

    with %{student: student} <- row(socket, student_id),
         {:ok, updated} <- store_entry(socket, student, entry) do
      {:noreply,
       socket |> replace_student(updated) |> assign(sheet: nil) |> photo_stored(student_id)}
    else
      nil ->
        discard_entry(socket, entry)

        {:noreply,
         photo_failed(socket, student_id, gettext("Cet élève n'est pas dans cette classe."))}

      {:error, message} ->
        {:noreply, photo_failed(socket, student_id, message)}
    end
  end

  defp row(socket, id), do: Enum.find(socket.assigns.roster, &(&1.student.id == id))

  defp replace_student(socket, updated) do
    socket
    |> update(:roster, fn rows ->
      Enum.map(rows, fn
        %{student: %{id: id}} = r when id == updated.id -> %{r | student: updated}
        r -> r
      end)
    end)
    |> assign_queue()
  end

  # Séance order (§7.2): without photo first, then — when redoing — everyone else; class list order.
  defp assign_queue(socket) do
    {missing, done} = Enum.split_with(socket.assigns.roster, &is_nil(&1.student.photo_path))
    rows = if socket.assigns.redo_all?, do: missing ++ done, else: missing
    assign(socket, :queue, Enum.map(rows, &%{id: &1.student.id, name: &1.student.full_name}))
  end

  defp with_photo(roster), do: Enum.count(roster, &is_binary(&1.student.photo_path))

  defp visible(roster, true), do: Enum.filter(roster, &is_nil(&1.student.photo_path))
  defp visible(roster, false), do: roster

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="class-photos" class="space-y-5">
        <.breadcrumb>
          <:crumb navigate={~p"/school/classes"}>{gettext("Classes")}</:crumb>
          <:crumb navigate={~p"/school/classes/#{@cg.id}"}>{@cg.label}</:crumb>
          <:crumb>{gettext("Photos")}</:crumb>
        </.breadcrumb>

        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="font-display text-3xl font-semibold leading-none">{gettext("Photos")}</h1>
            <p id="photo-count" class="ta-num mt-2 text-sm text-base-content/70">
              {gettext("%{done}/%{total} photos", done: with_photo(@roster), total: length(@roster))}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link
              href={~p"/school/classes/#{@cg.id}/cards/print"}
              target="_blank"
              id="go-to-cards"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-identification" class="size-4" /> {gettext("Cartes scolaires")}
            </.link>
            <button
              id="start-session"
              type="button"
              class="btn btn-primary btn-sm gap-1.5"
              disabled={@queue == []}
              phx-click={Phoenix.LiveView.JS.dispatch("photo:session-start", to: "#photo-studio")}
            >
              <.icon name="hero-camera" class="size-4" /> {gettext("Lancer la séance")}
            </button>
          </div>
        </header>

        <div class="flex flex-wrap items-center gap-4 text-sm">
          <label class="flex cursor-pointer items-center gap-2">
            <input
              id="only-missing"
              type="checkbox"
              class="toggle toggle-sm"
              checked={@only_missing?}
              phx-click="toggle_missing"
            />
            {gettext("Sans photo uniquement")}
          </label>
          <label class="flex cursor-pointer items-center gap-2">
            <input
              id="redo-all"
              type="checkbox"
              class="toggle toggle-sm"
              checked={@redo_all?}
              phx-click="toggle_redo_all"
            />
            {gettext("Séance : refaire toute la classe")}
          </label>
        </div>

        <.photo_upload_form upload={@uploads.photo} />

        <ul :if={@uploads.photo.entries != []} id="photo-uploads" class="space-y-1 text-sm">
          <li :for={entry <- @uploads.photo.entries} class="flex items-center gap-2">
            <progress class="progress progress-primary w-24" value={entry.progress} max="100"></progress>
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
            >×</button>
          </li>
        </ul>

        <ul id="photo-grid" class="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <li
            :for={row <- visible(@roster, @only_missing?)}
            id={"photo-#{row.student.id}"}
            data-photo-drop={row.student.id}
          >
            <button
              type="button"
              phx-click="open_sheet"
              phx-value-id={row.student.id}
              class="group block w-full overflow-hidden rounded-box border border-base-300 bg-base-100 text-left transition hover:-translate-y-0.5 hover:shadow-md"
            >
              <div class="relative aspect-[3/4] bg-base-200">
                <img
                  :if={row.student.photo_path}
                  src={student_photo_url(row.student)}
                  alt=""
                  loading="lazy"
                  class="size-full object-cover"
                />
                <div :if={!row.student.photo_path} class="grid size-full place-items-center">
                  <.student_avatar student={row.student} class="size-16 text-xl" />
                  <span class="badge badge-warning badge-sm absolute bottom-2 left-2">{gettext(
                    "Sans photo"
                  )}</span>
                </div>
              </div>
              <p class="truncate px-2 py-1.5 text-sm font-medium">{row.student.full_name}</p>
            </button>
          </li>
        </ul>

        <.photo_sheet
          :if={@sheet}
          student={row_student(@roster, @sheet)}
          confirm_remove?={@confirm_remove?}
        />
        <.photo_studio id="photo-studio" queue={@queue} student_id={@sheet} />
      </section>
    </Layouts.app>
    """
  end

  defp row_student(roster, id), do: Enum.find_value(roster, &(&1.student.id == id && &1.student))
end
