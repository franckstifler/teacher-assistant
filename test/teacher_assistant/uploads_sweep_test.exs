defmodule TeacherAssistant.UploadsSweepTest do
  @moduledoc "The weekly sweep deletes only files nothing points at (A9)."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos, TeacherFixtures, Uploads}

  @old {{2020, 1, 1}, {0, 0, 0}}

  setup do
    %{scope: scope, year: year, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    root = Path.join(System.tmp_dir!(), "sweep-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e S", level: "6ème"})
    {:ok, st} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    %{scope: scope, year: year, ws: ws, root: root, cg: cg, st: st}
  end

  # A file at `relative` under the test's own root, `mtime` old by default.
  defp put(root, relative, mtime \\ @old) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "x")
    File.touch!(path, mtime)
    path
  end

  defp stored_photo(ctx) do
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, st} = StudentPhotos.store(ctx.scope, ctx.st, tmp)
    st
  end

  test "deletes an old unreferenced photo and keeps the referenced one", ctx do
    st = stored_photo(ctx)
    kept = put(ctx.root, st.photo_path)
    gone = put(ctx.root, "student_photos/#{ctx.ws.id}/#{Ash.UUIDv7.generate()}.jpg")

    assert %{deleted: 1, kept: 1} = Uploads.sweep_orphans(ctx.root)
    assert File.exists?(kept)
    refute File.exists?(gone)
  end

  test "keeps a photo referenced only by a published bulletin's snapshot", ctx do
    :ok = TeacherFixtures.verify_school!(ctx.scope)
    st = stored_photo(ctx)
    [term | _] = TeacherAssistant.Organization.list_terms(ctx.scope, ctx.year)
    {:ok, _} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, term)
    {:ok, _} = StudentPhotos.remove(ctx.scope, st)
    frozen = put(ctx.root, st.photo_path)

    assert %{deleted: 0} = Uploads.sweep_orphans(ctx.root)
    assert File.exists?(frozen)
  end

  test "keeps a file younger than a day", ctx do
    fresh =
      put(
        ctx.root,
        "student_photos/#{ctx.ws.id}/#{Ash.UUIDv7.generate()}.jpg",
        :calendar.universal_time()
      )

    assert %{deleted: 0} = Uploads.sweep_orphans(ctx.root)
    assert File.exists?(fresh)
  end

  test "never touches files outside the three folders or at the root", ctx do
    probe = put(ctx.root, ".write_check")
    other = put(ctx.root, "exports/#{ctx.ws.id}/x.bin")
    logo = put(ctx.root, "school_logos/#{ctx.ws.id}/#{Ash.UUIDv7.generate()}.png")

    assert %{deleted: 1} = Uploads.sweep_orphans(ctx.root)
    assert File.exists?(probe)
    assert File.exists?(other)
    refute File.exists?(logo)
  end
end
