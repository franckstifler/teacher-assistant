defmodule TeacherAssistant.Academics.DisciplineTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Academics.SanctionEntry
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, cg_other} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    {:ok, _student1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, _student2} = Academics.add_student(cg, %{full_name: "Bilal", sex: :m})
    {:ok, _other_student} = Academics.add_student(cg_other, %{full_name: "Zara", sex: :f})

    roster = Academics.list_roster(cg)
    [%{enrollment: enrollment1}, %{enrollment: enrollment2}] = roster

    other_roster = Academics.list_roster(cg_other)
    [%{enrollment: other_enrollment}] = other_roster

    :ok = Academics.build_default_calendar(year)
    [seq1, seq2 | _] = Academics.list_sequences(year)

    %{
      head: head,
      ws: ws,
      year: year,
      cg: cg,
      cg_other: cg_other,
      enrollment1: enrollment1,
      enrollment2: enrollment2,
      other_enrollment: other_enrollment,
      seq1: seq1,
      seq2: seq2
    }
  end

  describe "add_sanction/3" do
    test "persists with the class's workspace_id", ctx do
      assert {:ok, %SanctionEntry{} = sanction} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{type: :avertissement, date: ctx.seq1.start_date, reason: "Retard répété"},
                 ctx.head.id
               )

      assert sanction.workspace_id == ctx.ws.id
      assert sanction.type == :avertissement
      assert sanction.reason == "Retard répété"
    end

    test "rejects an invalid type", ctx do
      assert {:error, :invalid_type} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{type: :expulsion, date: ctx.seq1.start_date},
                 ctx.head.id
               )
    end

    test "translates an Ash write failure (nil date) to a tagged error, not a raw struct", ctx do
      assert {:error, :sanction_failed} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{type: :avertissement, date: nil},
                 ctx.head.id
               )
    end

    test "keeps duration_days for exclusion_temporaire", ctx do
      assert {:ok, %SanctionEntry{} = sanction} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{
                   type: :exclusion_temporaire,
                   date: ctx.seq1.start_date,
                   duration_days: 3
                 },
                 ctx.head.id
               )

      assert sanction.duration_days == 3
    end

    test "drops duration_days (nil) for a consigne", ctx do
      assert {:ok, %SanctionEntry{} = sanction} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{
                   type: :consigne,
                   date: ctx.seq1.start_date,
                   duration_days: 2
                 },
                 ctx.head.id
               )

      assert sanction.duration_days == nil
    end

    test "drops duration_days (nil) for an avertissement", ctx do
      assert {:ok, %SanctionEntry{} = sanction} =
               Discipline.add_sanction(
                 ctx.enrollment1,
                 %{
                   type: :avertissement,
                   date: ctx.seq1.start_date,
                   duration_days: 5
                 },
                 ctx.head.id
               )

      assert sanction.duration_days == nil
    end
  end

  describe "list_sanctions/2" do
    test "class + période: returns only in-range sanctions newest-first, excludes out-of-range",
         ctx do
      {:ok, in_range1} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, in_range2} =
        Discipline.add_sanction(
          ctx.enrollment2,
          %{type: :blame, date: Date.add(ctx.seq1.start_date, 1)},
          ctx.head.id
        )

      {:ok, _out_of_range} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :blame, date: ctx.seq2.start_date},
          ctx.head.id
        )

      results = Discipline.list_sanctions(ctx.cg, {:sequence, ctx.seq1})

      assert Enum.map(results, & &1.id) == [in_range2.id, in_range1.id]
      assert Enum.all?(results, &(&1.enrollment.student != nil))
    end

    test "class + période excludes sanctions from another class", ctx do
      {:ok, _own} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, _other} =
        Discipline.add_sanction(
          ctx.other_enrollment,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      results = Discipline.list_sanctions(ctx.cg, {:sequence, ctx.seq1})

      assert length(results) == 1
      assert hd(results).enrollment_id == ctx.enrollment1.id
    end

    test "single enrollment scopes to that student", ctx do
      {:ok, mine} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, _other_student} =
        Discipline.add_sanction(
          ctx.enrollment2,
          %{type: :blame, date: ctx.seq1.start_date},
          ctx.head.id
        )

      results = Discipline.list_sanctions(ctx.enrollment1, {:sequence, ctx.seq1})

      assert Enum.map(results, & &1.id) == [mine.id]
    end

    test "class + période boundaries: includes start_date and end_date, excludes day after end_date",
         ctx do
      {:ok, on_start} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, on_end} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :blame, date: ctx.seq1.end_date},
          ctx.head.id
        )

      {:ok, _after_end} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :consigne, date: Date.add(ctx.seq1.end_date, 1)},
          ctx.head.id
        )

      results = Discipline.list_sanctions(ctx.cg, {:sequence, ctx.seq1})
      result_ids = MapSet.new(results, & &1.id)

      assert result_ids == MapSet.new([on_start.id, on_end.id])
    end

    test "returns [] when the period range is nil", ctx do
      empty_year_head = TeacherFixtures.user_fixture()
      {:ok, empty_ws} = Schools.create_school(empty_year_head, %{name: "Lycée Empty"})

      {:ok, empty_year} =
        Academics.create_academic_year(empty_ws, %{
          name: "2099-2100",
          start_date: ~D[2099-09-08],
          end_date: ~D[2100-07-31],
          active: false
        })

      assert Discipline.list_sanctions(ctx.cg, {:annual, empty_year}) == []
    end
  end

  describe "delete_sanction/1" do
    test "removes the row", ctx do
      {:ok, sanction} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: ctx.seq1.start_date},
          ctx.head.id
        )

      assert :ok = Discipline.delete_sanction(sanction)

      assert Discipline.list_sanctions(ctx.enrollment1, {:sequence, ctx.seq1}) == []
    end
  end
end
