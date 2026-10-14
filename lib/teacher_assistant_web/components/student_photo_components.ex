defmodule TeacherAssistantWeb.StudentPhotoComponents do
  @moduledoc "Spec 2026-10-12 §5/§7: student avatars and the photo studio markup."
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  import TeacherAssistantWeb.CoreComponents, only: [initials_avatar: 1]

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
end
