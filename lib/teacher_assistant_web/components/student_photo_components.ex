defmodule TeacherAssistantWeb.StudentPhotoComponents do
  @moduledoc "Spec 2026-10-12 §5/§7: student avatars and the photo studio markup."
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  import TeacherAssistantWeb.CoreComponents, only: [initials_avatar: 1, icon: 1]

  import Phoenix.LiveView,
    only: [allow_upload: 3, consume_uploaded_entry: 3, push_event: 3, put_flash: 3]

  alias TeacherAssistant.StudentPhotos
  alias TeacherAssistantWeb.Authz

  @doc "The current photo URL; `v` changes with each new photo so caches never serve a replaced one."
  def student_photo_url(%{id: id} = student) do
    case Map.get(student, :photo_taken_at) do
      %DateTime{} = at -> ~p"/school/students/#{id}/photo?v=#{DateTime.to_unix(at)}"
      _ -> ~p"/school/students/#{id}/photo"
    end
  end

  attr :student, :map, required: true
  attr :class, :string, default: "size-8 text-xs"

  def student_avatar(assigns) do
    ~H"""
    <img
      :if={is_binary(Map.get(@student, :photo_path))}
      src={student_photo_url(@student)}
      alt=""
      loading="lazy"
      class={["shrink-0 rounded-full bg-base-300 object-cover", @class]}
    />
    <.initials_avatar
      :if={!is_binary(Map.get(@student, :photo_path))}
      name={@student.full_name}
      class={@class}
    />
    """
  end

  attr :student, :map, required: true
  attr :confirm_remove?, :boolean, default: false

  def photo_sheet(assigns) do
    ~H"""
    <div
      id="photo-sheet"
      class="fixed inset-0 z-40 flex items-end justify-center bg-black/40 sm:items-center"
      phx-window-keydown="close_sheet"
      phx-key="Escape"
    >
      <div
        class="w-full max-w-sm space-y-3 rounded-t-box bg-base-100 p-4 shadow-xl sm:rounded-box"
        phx-click-away="close_sheet"
      >
        <p class="font-semibold">{@student.full_name}</p>
        <button
          id="pick-photo"
          type="button"
          class="btn btn-primary w-full"
          phx-click={Phoenix.LiveView.JS.dispatch("photo:pick", to: "#photo-studio")}
        >
          <.icon name="hero-camera" class="size-4" /> {gettext("Prendre / choisir une photo")}
        </button>
        <button
          :if={@student.photo_path && !@confirm_remove?}
          id="remove-photo"
          type="button"
          class="btn btn-ghost w-full text-error"
          phx-click="ask_remove"
        >
          {gettext("Supprimer la photo")}
        </button>
        <button
          :if={@confirm_remove?}
          id="confirm-remove-photo"
          type="button"
          class="btn btn-error w-full"
          phx-click="remove_photo"
        >
          {gettext("Confirmer la suppression")}
        </button>
        <button type="button" class="btn btn-ghost w-full" phx-click="close_sheet">{gettext("Annuler")}</button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :queue, :list, default: []
  attr :student_id, :string, default: nil

  def photo_studio(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="PhotoStudio"
      phx-update="ignore"
      data-student-id={@student_id}
      data-queue={Jason.encode!(@queue)}
    >
      <input type="file" accept="image/*" class="hidden" data-role="file" />

      <div
        data-role="crop"
        class="fixed inset-0 z-50 hidden flex-col items-center justify-center gap-4 bg-black/90 p-4 text-white"
      >
        <p class="text-sm opacity-80">
          {gettext("Faites glisser pour cadrer, zoomez avec le curseur.")}
        </p>
        <canvas
          data-role="crop-canvas"
          width="600"
          height="800"
          class="aspect-[3/4] w-[min(80vw,22rem)] touch-none rounded-box bg-black"
        ></canvas>
        <input
          data-role="zoom"
          type="range"
          min="1"
          max="3"
          step="0.01"
          value="1"
          class="range range-sm w-[min(80vw,22rem)]"
          aria-label={gettext("Zoom")}
        />
        <div class="flex gap-3">
          <button type="button" data-role="crop-cancel" class="btn btn-ghost">{gettext("Annuler")}</button>
          <button type="button" data-role="crop-ok" class="btn btn-primary">{gettext("Valider")}</button>
        </div>
      </div>

      <p
        data-role="pending"
        class="fixed bottom-4 right-4 z-50 hidden rounded-full bg-base-content px-3 py-1.5 text-sm text-base-100 shadow-lg"
        data-label-one={gettext("1 photo en cours d'envoi")}
        data-label-many={gettext("%{count} photos en cours d'envoi", count: "__N__")}
        data-label-failed={gettext("Réessayer")}
      >
      </p>

      <%!-- Séance overlay: filled in Task 5. --%>
    </div>
    """
  end

  # --- LiveView side (shared by the class photos page and the student page) ---

  @doc "Spec 2026-10-12 §7.4: the `:photo` auto-upload; the browser always sends a ≤ 1 MB JPEG."
  def allow_photo_upload(socket, progress) do
    allow_upload(socket, :photo,
      accept: ~w(.jpg .jpeg),
      max_entries: 5,
      max_file_size: 1_000_000,
      auto_upload: true,
      progress: progress
    )
  end

  @doc "The student id a `:photo` entry is for — the hook names the file `<student_id>.jpg`."
  def entry_student_id(entry), do: Path.rootname(entry.client_name)

  @doc "Consumes a finished `:photo` entry into `student`'s photo."
  def store_entry(socket, student, entry) do
    socket
    |> consume_uploaded_entry(entry, fn %{path: tmp} ->
      {:ok, StudentPhotos.store(socket.assigns.current_scope, student, tmp)}
    end)
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, %Ash.Error.Forbidden{}} -> {:error, Authz.not_allowed_message()}
      {:error, _} -> {:error, gettext("Photo refusée : fichier JPEG d'1 Mo maximum.")}
    end
  end

  @doc "Drops a finished `:photo` entry without storing it."
  def discard_entry(socket, entry),
    do: consume_uploaded_entry(socket, entry, fn _ -> {:ok, nil} end)

  @doc "Tells the user and the hook (which keeps the file for a retry) that an upload failed."
  def photo_failed(socket, student_id, message) do
    socket
    |> put_flash(:error, message)
    |> push_event("photo:failed", %{student_id: student_id, message: message})
  end

  @doc "Tells the hook the server stored `student_id`'s photo, so it drops the file."
  def photo_stored(socket, student_id),
    do: push_event(socket, "photo:stored", %{student_id: student_id})

  @doc "Removes `student`'s photo pointer (the file stays — spec §3)."
  def remove_photo(socket, student) do
    case StudentPhotos.remove(socket.assigns.current_scope, student) do
      {:ok, updated} -> {:ok, updated}
      {:error, %Ash.Error.Forbidden{}} -> {:error, Authz.not_allowed_message()}
      {:error, _} -> {:error, gettext("Impossible de supprimer la photo.")}
    end
  end

  def unreadable_message, do: gettext("Format d'image non pris en charge par ce navigateur.")

  attr :upload, :any, required: true

  @doc "The hidden form carrying the `:photo` upload the hook feeds."
  def photo_upload_form(assigns) do
    ~H"""
    <form
      id="photo-upload-form"
      phx-change="validate_photo"
      phx-submit="validate_photo"
      class="hidden"
    >
      <.live_file_input upload={@upload} />
    </form>
    """
  end
end
