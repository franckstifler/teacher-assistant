defmodule TeacherAssistant.StudentPhotosTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, StudentPhotos, Uploads}
  alias TeacherAssistant.TeacherFixtures

  @jpeg "test/support/fixtures/files/1x1.jpg"
  @png "test/support/fixtures/files/1x1.png"

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})
    {:ok, st} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngono", sex: :f})
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    %{scope: scope, cg: cg, st: st, sg: sg}
  end

  defp tmp_copy(src) do
    path = Path.join(System.tmp_dir!(), "ta-photo-#{System.unique_integer([:positive])}")
    File.cp!(src, path)
    path
  end

  defp stored_files(scope) do
    Path.join([Uploads.dir(), "student_photos", scope.current_workspace.id, "*.jpg"])
    |> Path.wildcard()
  end

  test "the SG stores a JPEG and the student points at it", %{sg: sg, st: st} do
    assert {:ok, updated} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    assert updated.photo_path =~ ~r{^student_photos/#{sg.current_workspace.id}/.+\.jpg$}
    assert %DateTime{} = updated.photo_taken_at
    assert {:ok, abs} = Uploads.resolve(updated.photo_path, sg.current_workspace.id)
    assert File.read!(abs) == File.read!(@jpeg)
  end

  test "replacing keeps the previous file", %{sg: sg, st: st} do
    {:ok, first} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    {:ok, second} = StudentPhotos.store(sg, first, tmp_copy(@jpeg))
    refute first.photo_path == second.photo_path
    assert {:ok, _} = Uploads.resolve(first.photo_path, sg.current_workspace.id)
  end

  test "a non-JPEG is refused and nothing is stored", %{sg: sg, st: st} do
    assert {:error, :invalid_image} = StudentPhotos.store(sg, st, tmp_copy(@png))
    assert stored_files(sg) == []
  end

  test "an empty file is refused", %{sg: sg, st: st} do
    path = tmp_copy(@jpeg)
    File.write!(path, "")
    assert {:error, :invalid_image} = StudentPhotos.store(sg, st, path)
  end

  test "a file over 1 MB is refused", %{sg: sg, st: st} do
    path = tmp_copy(@jpeg)
    File.write!(path, [<<0xFF, 0xD8, 0xFF>>, :binary.copy(<<0>>, 1_000_000)])
    assert {:error, :too_large} = StudentPhotos.store(sg, st, path)
  end

  test "a teacher or a form master is forbidden and the copied file is removed",
       %{scope: scope, cg: cg, st: st} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.current_user.id)

    assert {:error, %Ash.Error.Forbidden{}} = StudentPhotos.store(teacher, st, tmp_copy(@jpeg))
    assert stored_files(teacher) == []
  end

  test "remove clears the pointer but keeps the file", %{sg: sg, st: st} do
    {:ok, with_photo} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    assert {:ok, removed} = StudentPhotos.remove(sg, with_photo)
    assert removed.photo_path == nil and removed.photo_taken_at == nil
    assert {:ok, _} = Uploads.resolve(with_photo.photo_path, sg.current_workspace.id)
  end

  test "resolve refuses paths escaping the uploads dir" do
    assert :error = Uploads.resolve("../../etc/passwd", "ws")
    assert :error = Uploads.resolve(nil, "ws")
  end

  test "resolve serves a school's file to that school only", %{sg: sg, st: st} do
    {:ok, %{photo_path: relative}} = StudentPhotos.store(sg, st, tmp_copy(@jpeg))
    ws = sg.current_workspace.id

    assert {:ok, _} = Uploads.resolve(relative, ws)
    assert :error = Uploads.resolve(relative, Ash.UUIDv7.generate())
    assert :error = Uploads.resolve(relative, nil)
    # the right school's name, reached by climbing out of another folder
    assert :error =
             Uploads.resolve("student_photos/x/../#{ws}/../../#{relative}", Ash.UUIDv7.generate())

    # not deeper, not shallower than folder/school/file
    assert :error = Uploads.resolve(Path.dirname(relative), ws)
  end
end
