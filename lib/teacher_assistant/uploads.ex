defmodule TeacherAssistant.Uploads do
  @moduledoc "The uploads directory and the one safe way to turn a stored relative path into a file."

  @image_types %{".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg"}

  def dir, do: :teacher_assistant |> Application.fetch_env!(:uploads_dir) |> Path.expand()

  @doc "The absolute path of a stored relative path, or `:error` when it escapes `dir/0` or is not a regular file."
  def resolve(relative) when is_binary(relative) do
    root = dir()
    path = Path.expand(Path.join(root, relative))

    if String.starts_with?(path, root <> "/") and File.regular?(path),
      do: {:ok, path},
      else: :error
  end

  def resolve(_), do: :error

  @doc """
  Copies an uploaded PNG or JPEG to `folder/workspace_id/` under a name and
  extension chosen here from the file's own bytes — never from the client's
  file name or type, which an uploader controls. Returns `{:ok, relative_path}`
  or `{:error, :invalid_image}`.
  """
  def store_image(tmp_path, folder, workspace_id) do
    with {:ok, ext} <- image_extension(tmp_path) do
      relative = Path.join([folder, workspace_id, Ash.UUIDv7.generate() <> ext])
      dest = Path.join(dir(), relative)
      dest |> Path.dirname() |> File.mkdir_p!()
      File.cp!(tmp_path, dest)
      {:ok, relative}
    end
  end

  @doc "The image content type to serve a stored file with, or `:error` for anything but PNG/JPEG."
  def image_content_type(path) do
    Map.fetch(@image_types, path |> Path.extname() |> String.downcase())
  end

  defp image_extension(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 8)) do
      {:ok, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>} -> {:ok, ".png"}
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> {:ok, ".jpg"}
      _ -> {:error, :invalid_image}
    end
  end
end
