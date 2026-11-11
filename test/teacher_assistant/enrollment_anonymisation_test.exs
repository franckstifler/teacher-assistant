defmodule TeacherAssistant.EnrollmentAnonymisationTest do
  @moduledoc "A departed student's record is anonymised three years later (A9)."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, Organization, StudentPhotos, TeacherFixtures, Uploads}
  alias TeacherAssistant.Academics.Guardian

  require Ash.Query

  @today ~D[2025-09-15]

  setup do
    %{scope: scope, year: year, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})

    {:ok, %{enrollment: e, student: awa}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa Nkolo", sex: :f})

    %{scope: scope, year: year, ws: ws, cg: cg, e: e, awa: awa}
  end

  defp leave(ctx, e, left_on),
    do:
      {:ok, _} = Enrollment.leave(ctx.scope, e, %{departure_reason: :transfer, left_on: left_on})

  defp reload(ctx, student),
    do: Ash.get!(TeacherAssistant.Academics.Student, student.id, scope: ctx.scope)

  test "a student departed more than three years ago is anonymised: name, ids, guardians, photo file",
       ctx do
    tmp = Path.join(System.tmp_dir!(), "ta-#{System.unique_integer([:positive])}.jpg")
    File.cp!("test/support/fixtures/files/1x1.jpg", tmp)
    {:ok, awa} = StudentPhotos.store(ctx.scope, ctx.awa, tmp)

    {:ok, awa} =
      Enrollment.update_student(awa, %{national_id: "123456", birth_place: "Yaoundé"},
        scope: ctx.scope
      )

    {:ok, guardian} =
      Enrollment.add_guardian(ctx.scope, awa, %{
        full_name: "Marie Nkolo",
        phone: "677000001",
        relationship: :mere
      })

    {:ok, photo} = Uploads.resolve(awa.photo_path, ctx.ws.id)
    leave(ctx, ctx.e, ~D[2022-06-01])

    assert %{anonymised: 1} = Enrollment.anonymise_due_students(ctx.ws.id, @today)

    student = reload(ctx, awa)
    assert student.full_name == "Élève parti"
    assert {student.national_id, student.birth_place, student.photo_path} == {nil, nil, nil}
    assert Enrollment.list_guardian_links(ctx.scope, student) == []
    refute Guardian |> Ash.Query.filter(id == ^guardian.id) |> Ash.exists?(scope: ctx.scope)
    refute File.exists?(photo)
  end

  test "a sibling's guardian survives the anonymisation", ctx do
    {:ok, %{student: bilal}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Bilal Nkolo", sex: :m})

    {:ok, guardian} =
      Enrollment.add_guardian(ctx.scope, ctx.awa, %{
        full_name: "Marie Nkolo",
        phone: "677000002",
        relationship: :mere
      })

    {:ok, _} = Enrollment.link_guardian(ctx.scope, bilal, guardian)
    leave(ctx, ctx.e, ~D[2022-06-01])

    assert %{anonymised: 1} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
    assert [%{guardian: %{id: id}}] = Enrollment.list_guardian_links(ctx.scope, bilal)
    assert id == guardian.id
  end

  test "three years minus a day is not due; three years exactly is", ctx do
    leave(ctx, ctx.e, ~D[2022-09-16])
    assert %{anonymised: 0} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
    assert %{anonymised: 1} = Enrollment.anonymise_due_students(ctx.ws.id, ~D[2025-09-16])
  end

  test "a year that ended three years ago, with no departure, is due", ctx do
    {:ok, old} =
      Organization.create_academic_year(ctx.scope, %{
        name: "2021-2022",
        start_date: ~D[2021-09-06],
        end_date: ~D[2022-07-31],
        active: false
      })

    {:ok, old_cg} = Enrollment.create_class_group(ctx.scope, old, %{label: "3e Z", level: "3ème"})

    {:ok, %{student: zoe}} =
      Enrollment.enroll_new(ctx.scope, old_cg, %{full_name: "Zoé Ancienne", sex: :f})

    assert %{anonymised: 1} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
    assert reload(ctx, zoe).full_name == "Élève parti"
    assert reload(ctx, ctx.awa).full_name == "Awa Nkolo"
  end

  test "a student with a later enrollment is never due", ctx do
    {:ok, old} =
      Organization.create_academic_year(ctx.scope, %{
        name: "2021-2022",
        start_date: ~D[2021-09-06],
        end_date: ~D[2022-07-31],
        active: false
      })

    {:ok, old_cg} = Enrollment.create_class_group(ctx.scope, old, %{label: "3e Z", level: "3ème"})
    {:ok, _} = Enrollment.enroll_existing(ctx.scope, old_cg, ctx.awa)

    assert %{anonymised: 0} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
  end

  test "an already anonymised student is not counted again", ctx do
    leave(ctx, ctx.e, ~D[2022-06-01])
    assert %{anonymised: 1} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
    assert %{anonymised: 0} = Enrollment.anonymise_due_students(ctx.ws.id, @today)
  end

  test "another workspace's student is untouched", ctx do
    %{workspace: other_ws} = TeacherFixtures.setup_complete_school_fixture()
    leave(ctx, ctx.e, ~D[2022-06-01])
    assert %{anonymised: 0} = Enrollment.anonymise_due_students(other_ws.id, @today)
    assert reload(ctx, ctx.awa).full_name == "Awa Nkolo"
  end
end
