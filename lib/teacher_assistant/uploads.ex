defmodule TeacherAssistant.Uploads do
  @moduledoc "The uploads directory and the one safe way to turn a stored relative path into a file."

  @image_types %{".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg"}

  def dir, do: :teacher_assistant |> Application.fetch_env!(:uploads_dir) |> Path.expand()

  @doc """
  The absolute path of a stored relative path, or `:error` unless it is a regular
  file inside `workspace_id`'s own folder (`folder/workspace_id/file`, as every
  store writes it): a path that leaves `dir/0`, or names another school's folder,
  is never served.
  """
  def resolve(relative, workspace_id) when is_binary(relative) and is_binary(workspace_id) do
    root = dir()
    path = Path.expand(Path.join(root, relative))

    with true <- String.starts_with?(path, root <> "/"),
         [_folder, ^workspace_id, _file] <- path |> Path.relative_to(root) |> Path.split(),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> :error
    end
  end

  def resolve(_relative, _workspace_id), do: :error

  @doc """
  Deletes a stored file (A9: anonymisation, the orphan sweep). Same path rules as
  `resolve/2`; `:ok` when the file is already gone, `:error` for a path outside the
  school's folder.
  """
  def delete(relative, workspace_id) when is_binary(relative) and is_binary(workspace_id) do
    root = dir()
    path = Path.expand(Path.join(root, relative))

    with true <- String.starts_with?(path, root <> "/"),
         [_folder, ^workspace_id, _file] <- path |> Path.relative_to(root) |> Path.split() do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, _} = error -> error
      end
    else
      _ -> :error
    end
  end

  def delete(_relative, _workspace_id), do: :error

  # --- Orphan sweep (A9) ----------------------------------------------------------

  @swept_folders ~w(student_photos school_logos school_signatures)

  @doc """
  Every stored path a row still points at: students' photos, schools' logo, signature
  and stamp, and the photos frozen in every bulletin publication's snapshot (a
  published bulletin keeps its photo after the student's changes). Internal reads
  across schools, for the weekly sweep only.
  """
  def referenced_paths do
    import Ecto.Query, only: [from: 2]
    alias TeacherAssistant.Repo

    photos =
      Repo.all(from(s in "students", where: not is_nil(s.photo_path), select: s.photo_path))

    profile_files =
      from(p in "school_profiles", select: [p.logo_path, p.signature_path, p.stamp_path])
      |> Repo.all()
      |> List.flatten()

    [photos, profile_files, snapshot_photos()]
    |> Enum.concat()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp snapshot_photos do
    alias TeacherAssistant.Academics.{BulletinPublication, Workspace}

    Workspace
    |> Ash.read!(authorize?: false)
    |> Enum.flat_map(fn ws ->
      BulletinPublication
      |> Ash.Query.select([:id, :snapshot])
      |> Ash.read!(tenant: ws.id, authorize?: false)
      |> Enum.flat_map(fn pub ->
        for entry <- Map.get(pub.snapshot || %{}, :roster, []),
            path = get_in(entry, [:student, :photo_path]),
            do: path
      end)
    end)
  end

  @doc """
  Deletes the files under `root` (default `dir/0`) that nothing points at
  (`referenced_paths/0`) and that are older than a day — a file stored a moment ago
  may not be on its row yet. Only `folder/workspace_id/file` inside the three upload
  folders is considered; the root and any other folder are left alone. Options:
  `:referenced` (a set of relative paths), `:older_than` (a `DateTime`). Returns
  `%{deleted: n, kept: n}`.
  """
  def sweep_orphans(root \\ dir(), opts \\ []) do
    referenced = Keyword.get_lazy(opts, :referenced, &referenced_paths/0)

    cutoff =
      opts
      |> Keyword.get_lazy(:older_than, fn -> DateTime.add(DateTime.utc_now(), -1, :day) end)
      |> DateTime.to_unix()

    for folder <- @swept_folders,
        school <- ls(Path.join(root, folder)),
        file <- ls(Path.join([root, folder, school])),
        relative = Path.join([folder, school, file]),
        path = Path.join(root, relative),
        reduce: %{deleted: 0, kept: 0} do
      acc ->
        case File.stat(path, time: :posix) do
          {:ok, %{type: :regular, mtime: mtime}} ->
            if mtime < cutoff and not MapSet.member?(referenced, relative) do
              File.rm!(path)
              Map.update!(acc, :deleted, &(&1 + 1))
            else
              Map.update!(acc, :kept, &(&1 + 1))
            end

          _ ->
            acc
        end
    end
  end

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      {:error, _} -> []
    end
  end

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
