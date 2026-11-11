defmodule TeacherAssistant.Academics.Fees2DataTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.{AttendanceStatus, FeeSendOut, FeeWarning, ReturnNote}
  alias TeacherAssistant.{Enrollment, FeesFixtures, TeacherFixtures}

  setup do
    FeesFixtures.fees_school_fixture()
  end

  defp create(resource, attrs, scope),
    do: resource |> paper_changeset(:create, attrs, scope: scope) |> Ash.create()

  defp send_out(ctx, date),
    do:
      create(
        FeeSendOut,
        %{enrollment_id: ctx.e.id, academic_year_id: ctx.year.id, date: date},
        ctx.scope
      )

  defp note_attrs(ctx, seq, overrides \\ %{}),
    do:
      Map.merge(
        %{
          enrollment_id: ctx.e.id,
          academic_year_id: ctx.year.id,
          seq: seq,
          number: "A2025-#{String.pad_leading(to_string(seq), 6, "0")}",
          reason: :promise,
          issued_on: ~D[2025-09-15],
          valid_until: ~D[2025-09-30],
          student_name: "Awa A",
          class_label: "6e Q"
        },
        overrides
      )

  defp warning_attrs(ctx, seq),
    do: %{
      enrollment_id: ctx.e.id,
      academic_year_id: ctx.year.id,
      seq: seq,
      number: "V2025-#{String.pad_leading(to_string(seq), 6, "0")}",
      issued_on: ~D[2025-09-15],
      pay_by: ~D[2025-09-22],
      lines: [%{name: "Frais exigibles", amount: 24_000}],
      total: 24_000,
      student_name: "Awa A",
      class_label: "6e Q"
    }

  test "a send-out is unique per student and day", ctx do
    assert {:ok, _} = send_out(ctx, ~D[2025-09-15])
    assert {:error, _} = send_out(ctx, ~D[2025-09-15])
    assert {:ok, _} = send_out(ctx, ~D[2025-09-16])
  end

  test "a teacher can read send-outs but not create them", ctx do
    {:ok, row} = send_out(ctx, ~D[2025-09-15])
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    refute Ash.can?({FeeSendOut, :create}, teacher)
    assert {:ok, _} = Ash.get(FeeSendOut, row.id, scope: teacher)
  end

  test "a note's valid_until cannot be before issued_on", ctx do
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             create(ReturnNote, note_attrs(ctx, 1, %{valid_until: ~D[2025-09-14]}), ctx.scope)

    assert Enum.any?(errors, &(&1.field == :valid_until))
  end

  test "cancel requires a reason and refuses twice", ctx do
    {:ok, note} = create(ReturnNote, note_attrs(ctx, 1), ctx.scope)
    {:ok, warning} = create(FeeWarning, warning_attrs(ctx, 1), ctx.scope)

    for row <- [note, warning] do
      assert {:error, _} =
               row
               |> Ash.Changeset.for_update(:cancel, %{reason: " "}, scope: ctx.scope)
               |> Ash.update()

      assert {:ok, cancelled} =
               row
               |> Ash.Changeset.for_update(:cancel, %{reason: "Erreur"}, scope: ctx.scope)
               |> Ash.update()

      assert cancelled.status == :cancelled

      assert {:error, _} =
               cancelled
               |> Ash.Changeset.for_update(:cancel, %{reason: "Encore"}, scope: ctx.scope)
               |> Ash.update()
    end
  end

  test "a warning keeps its frozen lines", ctx do
    {:ok, warning} = create(FeeWarning, warning_attrs(ctx, 1), ctx.scope)
    assert [%{name: "Frais exigibles", amount: 24_000}] = warning.lines
  end

  test "notes are read by the fees axis and the class's form master only", ctx do
    {:ok, _} = create(ReturnNote, note_attrs(ctx, 1), ctx.scope)
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)

    assert [_] = TeacherAssistant.FeeControl.list_notes(fm, ctx.e)
    assert [] = TeacherAssistant.FeeControl.list_notes(teacher, ctx.e)
  end

  test "a student with a note cannot be withdrawn", ctx do
    {:ok, _} = create(ReturnNote, note_attrs(ctx, 1), ctx.scope)
    assert {:error, _} = Enrollment.remove_mistaken(ctx.scope, ctx.e)
  end

  test "AttendanceStatus has sent_home" do
    assert :sent_home in AttendanceStatus.values()
    assert AttendanceStatus.label(:sent_home) == "Renvoyé pour frais"
  end
end
