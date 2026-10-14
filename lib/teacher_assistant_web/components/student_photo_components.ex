defmodule TeacherAssistantWeb.StudentPhotoComponents do
  @moduledoc "Spec 2026-10-12 §5/§7: student avatars and the photo studio markup."
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  import TeacherAssistantWeb.CoreComponents, only: [initials_avatar: 1, icon: 1]

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
      data-student-id={@student_id}
      data-queue={Jason.encode!(@queue)}
    >
    </div>
    """
  end
end
