defmodule TeacherAssistant.StudentPhotos do
  @moduledoc """
  Spec 2026-10-12 §3: student photo files. A file is never overwritten, and is
  deleted in two cases only (A9): the student's anonymisation three years after they
  left, and the weekly sweep of files nothing points at (a published bulletin's
  snapshot counts as pointing at its photo).
  """
  alias TeacherAssistant.{Enrollment, Scope, Uploads}
  alias TeacherAssistant.Academics.Student

  @max_bytes 1_000_000

  def store(%Scope{current_workspace: %{id: ws_id}} = scope, %Student{} = student, tmp_path) do
    with :ok <- check_size(tmp_path),
         :ok <- check_jpeg(tmp_path) do
      relative = Path.join(["student_photos", ws_id, Ash.UUIDv7.generate() <> ".jpg"])
      dest = Path.join(Uploads.dir(), relative)
      dest |> Path.dirname() |> File.mkdir_p!()
      File.cp!(tmp_path, dest)

      case Enrollment.set_student_photo(student, %{photo_path: relative}, scope: scope) do
        {:ok, updated} ->
          {:ok, updated}

        {:error, error} ->
          File.rm(dest)
          {:error, error}
      end
    end
  end

  def remove(%Scope{} = scope, %Student{} = student),
    do: Enrollment.remove_student_photo(student, scope: scope)

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_bytes -> {:error, :too_large}
      {:ok, %{size: size}} when size > 0 -> :ok
      _ -> {:error, :invalid_image}
    end
  end

  defp check_jpeg(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 3)) do
      {:ok, <<0xFF, 0xD8, 0xFF>>} -> :ok
      _ -> {:error, :invalid_image}
    end
  end
end
