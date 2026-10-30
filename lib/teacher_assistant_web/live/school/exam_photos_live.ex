defmodule TeacherAssistantWeb.School.ExamPhotosLive do
  @moduledoc """
  Spec 2026-10-29: the candidates' exam pictures. One line per 1ère/Terminale class with
  its two codes; the ticked students with a photo are drawn and zipped in the browser
  (`ExamPhotos`/`ExamCard` hooks). The stored photos are only read.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, ExamPhotos}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Authz
  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_photo_url: 1]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Enrollment.can_manage_register?(scope) do
      classes = exam_classes(scope)

      {:ok,
       assign(socket,
         page_title: gettext("Photos examen"),
         classes: classes,
         open: nil,
         ticked: MapSet.new(for c <- classes, s <- c.students, do: s.id)
       )}
    else
      _ -> {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school")}
    end
  end

  defp exam_classes(%{current_academic_year: nil}), do: []

  defp exam_classes(scope) do
    scope
    |> Enrollment.list_class_groups(scope.current_academic_year)
    |> Enum.filter(&(&1.level in ExamPhotos.exam_levels()))
    |> Enum.map(fn cg ->
      %{cg: cg, students: scope |> Enrollment.list_roster(cg) |> Enum.map(& &1.student)}
    end)
  end

  def handle_event("open", %{"class" => id}, socket),
    do: {:noreply, update(socket, :open, &if(&1 == id, do: nil, else: id))}

  def handle_event("toggle", %{"student" => id}, socket) do
    ticked = socket.assigns.ticked

    {:noreply,
     set_ticked(
       socket,
       if(MapSet.member?(ticked, id), do: MapSet.delete(ticked, id), else: MapSet.put(ticked, id))
     )}
  end

  def handle_event("tick_all", %{"class" => id}, socket),
    do: {:noreply, set_ticked(socket, MapSet.union(socket.assigns.ticked, class_ids(socket, id)))}

  def handle_event("tick_none", %{"class" => id}, socket) do
    {:noreply,
     set_ticked(socket, MapSet.difference(socket.assigns.ticked, class_ids(socket, id)))}
  end

  # The hook keeps the unticked students in the tab's storage and hands them back when the
  # page mounts again (reconnect after the phone slept, back from taking a photo).
  def handle_event("restore_unticked", %{"ids" => ids}, socket) when is_list(ids),
    do: {:noreply, set_ticked(socket, MapSet.difference(socket.assigns.ticked, MapSet.new(ids)))}

  def handle_event("save_codes", %{"class_id" => id} = params, socket) do
    codes = %{exam_code: params["exam_code"], exam_center_code: params["exam_center_code"]}
    {:noreply, set_codes(socket, [id], codes)}
  end

  # The default CR code goes to the classes that have none; the others keep theirs.
  def handle_event("fill_center", %{"center" => center}, socket) do
    ids = for %{cg: cg} <- socket.assigns.classes, is_nil(cg.exam_center_code), do: cg.id

    message =
      case length(ids) do
        0 ->
          gettext("Toutes les classes ont déjà un code CR.")

        n ->
          ngettext("Code CR ajouté à %{count} classe.", "Code CR ajouté à %{count} classes.", n)
      end

    {:noreply, socket |> put_flash(:info, message) |> set_codes(ids, %{exam_center_code: center})}
  end

  def handle_event("export", %{"class" => id}, socket),
    do: {:noreply, export(socket, Enum.filter(socket.assigns.classes, &(&1.cg.id == id)))}

  def handle_event("export", _params, socket),
    do: {:noreply, export(socket, socket.assigns.classes)}

  # The hook skips a picture whose photo could not be read, and says how many.
  def handle_event("export_failed", %{"count" => count}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       ngettext(
         "%{count} photo n'a pas pu être préparée ; elle manque dans le zip.",
         "%{count} photos n'ont pas pu être préparées ; elles manquent dans le zip.",
         count
       )
     )}
  end

  defp set_ticked(socket, ticked) do
    all = for %{students: students} <- socket.assigns.classes, s <- students, do: s.id

    socket
    |> assign(:ticked, ticked)
    |> push_event("exam-photos:unticked", %{ids: Enum.reject(all, &MapSet.member?(ticked, &1))})
  end

  defp class_ids(socket, id) do
    for %{cg: %{id: ^id}, students: students} <- socket.assigns.classes,
        s <- students,
        into: MapSet.new(),
        do: s.id
  end

  defp set_codes(socket, ids, codes) do
    scope = socket.assigns.current_scope

    Enum.reduce(ids, socket, fn id, socket ->
      case Enum.find(socket.assigns.classes, &(&1.cg.id == id)) do
        nil -> socket
        %{cg: cg} -> save_codes(socket, cg, codes, scope)
      end
    end)
  end

  defp save_codes(socket, cg, codes, scope) do
    case Enrollment.set_exam_codes(cg, codes, scope: scope) do
      {:ok, updated} ->
        update(socket, :classes, fn classes ->
          Enum.map(classes, fn
            %{cg: %{id: id}} = c when id == cg.id -> %{c | cg: updated}
            c -> c
          end)
        end)

      {:error, _} ->
        put_flash(
          socket,
          :error,
          gettext("Impossible d'enregistrer les codes de %{class}.", class: cg.label)
        )
    end
  end

  defp export(socket, classes) do
    folders = ExamPhotos.folder_names(Enum.map(socket.assigns.classes, & &1.cg))

    case export_items(classes, socket.assigns.ticked, folders) do
      [] ->
        put_flash(socket, :error, gettext("Aucune photo à exporter."))

      items ->
        push_event(socket, "exam-photos:build", %{zip_name: zip_name(classes), items: items})
    end
  end

  defp zip_name([%{cg: cg}]), do: "photos-examen-#{ExamPhotos.safe_segment(cg.label)}.zip"
  defp zip_name(_classes), do: "photos-examen-#{Date.to_iso8601(Reference.today())}.zip"

  defp export_items(classes, ticked, folders) do
    for %{cg: cg, students: students} <- classes,
        files = ExamPhotos.file_names(exam_code(cg), students),
        s <- students,
        MapSet.member?(ticked, s.id) and has_photo?(s) do
      Map.merge(card(cg, s), %{folder: folders[cg.id], file: files[s.id]})
    end
  end

  # What the picture shows (the preview canvas and the exported file draw the same).
  defp card(cg, student) do
    %{
      photo_url: student_photo_url(student),
      date: ExamPhotos.photo_date(student.photo_taken_at),
      names: ExamPhotos.name_variants(student.full_name),
      codes: ExamPhotos.codes_line(exam_code(cg), cg.exam_center_code)
    }
  end

  # Until the user types one, the class's suggested code is the one used.
  defp exam_code(cg), do: cg.exam_code || ExamPhotos.suggested_exam_code(cg.level, cg.serie)

  defp has_photo?(student), do: is_binary(student.photo_path)

  defp ready(students), do: Enum.count(students, &has_photo?/1)

  defp exportable(classes, ticked) do
    for %{students: students} <- classes,
        s <- students,
        MapSet.member?(ticked, s.id) and has_photo?(s),
        reduce: 0,
        do: (n -> n + 1)
  end

  defp left_out(classes, ticked) do
    for %{students: students} <- classes,
        s <- students,
        MapSet.member?(ticked, s.id) and not has_photo?(s),
        reduce: 0,
        do: (n -> n + 1)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="exam-photos" phx-hook="ExamPhotos" class="space-y-5">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="font-display text-3xl font-semibold leading-none">
              {gettext("Photos examen")}
            </h1>
            <p class="mt-2 text-sm text-base-content/70">
              {gettext("Les photos des candidats de 1ère et de Terminale, au format de l'examen.")}
            </p>
          </div>
          <button
            id="exam-zip-selection"
            type="button"
            class="btn btn-primary btn-sm gap-1.5"
            phx-click="export"
            disabled={exportable(@classes, @ticked) == 0}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
            {ngettext(
              "Télécharger la sélection · %{count} photo",
              "Télécharger la sélection · %{count} photos",
              exportable(@classes, @ticked)
            )}
          </button>
        </header>

        <p
          id="exam-progress"
          data-role="progress"
          phx-update="ignore"
          data-label={gettext("Préparation des photos… %{n}/%{total}", n: "__N__", total: "__T__")}
          class="fixed inset-x-4 bottom-24 z-50 mx-auto hidden max-w-sm rounded-full bg-base-content px-4 py-2 text-center text-sm font-semibold text-base-100 shadow-lg"
          aria-live="polite"
        >
        </p>

        <form
          id="exam-default-center"
          phx-submit="fill_center"
          class="flex flex-wrap items-end gap-2 rounded-box bg-base-200/60 p-3"
        >
          <div class="w-44">
            <.input
              name="center"
              value=""
              label={gettext("Code CR par défaut")}
              placeholder="CR 8127"
            />
          </div>
          <button class="btn btn-ghost btn-sm mb-2">
            {gettext("Appliquer aux classes sans code CR")}
          </button>
        </form>

        <p
          :if={(n = left_out(@classes, @ticked)) > 0}
          id="exam-left-out"
          class="rounded-box bg-warning/15 px-3 py-2 text-sm text-warning"
        >
          <.icon name="hero-exclamation-triangle" class="size-4" />
          {ngettext(
            "%{count} élève coché sans photo ne sera pas exporté.",
            "%{count} élèves cochés sans photo ne seront pas exportés.",
            n
          )}
        </p>

        <p :if={@classes == []} class="text-sm text-base-content/70">
          {gettext("Aucune classe de 1ère ou de Terminale cette année.")}
        </p>

        <ul class="space-y-3">
          <li
            :for={%{cg: cg, students: students} = class <- @classes}
            id={"exam-class-#{cg.id}"}
            class="ta-panel space-y-3"
          >
            <div class="flex flex-wrap items-end gap-x-4 gap-y-2">
              <button
                id={"exam-open-#{cg.id}"}
                type="button"
                phx-click="open"
                phx-value-class={cg.id}
                class="flex min-h-11 items-center gap-1.5 font-semibold"
              >
                <.icon
                  name={if @open == cg.id, do: "hero-chevron-down", else: "hero-chevron-right"}
                  class="size-4"
                />
                {cg.label}
              </button>
              <form id={"exam-codes-#{cg.id}"} phx-change="save_codes" class="flex gap-2">
                <input type="hidden" name="class_id" value={cg.id} />
                <div class="w-28">
                  <.input
                    name="exam_code"
                    value={exam_code(cg)}
                    label={gettext("Code examen")}
                    phx-debounce="600"
                  />
                </div>
                <div class="w-28">
                  <.input
                    name="exam_center_code"
                    value={cg.exam_center_code}
                    label={gettext("Code CR")}
                    phx-debounce="600"
                  />
                </div>
              </form>
              <p id={"exam-count-#{cg.id}"} class="ta-num mb-2 text-sm">
                {ready(students)} / {length(students)}
                <span :if={ready(students) < length(students)} class="font-semibold text-warning">
                  · {ngettext(
                    "%{count} sans photo",
                    "%{count} sans photo",
                    length(students) - ready(students)
                  )}
                </span>
              </p>
              <button
                id={"exam-zip-#{cg.id}"}
                type="button"
                class="btn btn-outline btn-primary btn-sm mb-2 ml-auto"
                phx-click="export"
                phx-value-class={cg.id}
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
                {gettext("Zip · %{count}", count: exportable([class], @ticked))}
              </button>
            </div>

            <div :if={@open == cg.id} class="space-y-3 border-t border-base-300 pt-3">
              <div class="flex gap-2 text-sm">
                <button
                  id={"exam-all-#{cg.id}"}
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="tick_all"
                  phx-value-class={cg.id}
                >
                  {gettext("Tous")}
                </button>
                <button
                  id={"exam-none-#{cg.id}"}
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="tick_none"
                  phx-value-class={cg.id}
                >
                  {gettext("Aucun")}
                </button>
              </div>
              <ul class="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
                <li :for={s <- students} class="space-y-1.5">
                  <label class="flex cursor-pointer items-center gap-2 text-sm">
                    <input
                      id={"exam-tick-#{s.id}"}
                      type="checkbox"
                      class="checkbox checkbox-sm checkbox-primary"
                      checked={MapSet.member?(@ticked, s.id)}
                      phx-click="toggle"
                      phx-value-student={s.id}
                    />
                    <span class="truncate">{s.full_name}</span>
                  </label>
                  <canvas
                    :if={has_photo?(s)}
                    id={"exam-card-#{s.id}"}
                    phx-hook="ExamCard"
                    data-card={Jason.encode!(card(cg, s))}
                    data-unreadable={gettext("Photo illisible")}
                    width="300"
                    height="512"
                    class={[
                      "h-auto w-full rounded border border-base-300 bg-white transition",
                      !MapSet.member?(@ticked, s.id) && "opacity-40"
                    ]}
                  ></canvas>
                  <.link
                    :if={!has_photo?(s)}
                    navigate={~p"/school/classes/#{cg.id}/photos"}
                    class="grid aspect-[600/1024] place-items-center rounded border border-dashed border-warning p-2 text-center text-sm text-warning"
                  >
                    <span>
                      {gettext("Sans photo")}<br />
                      <span class="underline">{gettext("Prendre la photo")}</span>
                    </span>
                  </.link>
                </li>
              </ul>
            </div>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
