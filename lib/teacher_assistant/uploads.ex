defmodule TeacherAssistant.Uploads do
  @moduledoc "The uploads directory and the one safe way to turn a stored relative path into a file."

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
end
