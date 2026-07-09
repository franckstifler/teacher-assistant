defmodule TeacherAssistant.Academics.DisciplineTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ConductMark
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

  describe "set_conduct_mark/4" do
    test "creates a mark with the enrollment's workspace_id", ctx do
      assert {:ok, %ConductMark{} = mark} =
               Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 15, ctx.head.id)

      assert mark.value == Decimal.new(15)
      assert mark.workspace_id == ctx.ws.id
      assert mark.enrollment_id == ctx.enrollment1.id
      assert mark.sequence_id == ctx.seq1.id
    end

    test "re-setting the same (enrollment, sequence) upserts: one row, latest value", ctx do
      assert {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 12, ctx.head.id)

      assert {:ok, updated} =
               Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 18, ctx.head.id)

      assert Decimal.equal?(updated.value, Decimal.new(18))

      all =
        ConductMark
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id and sequence_id == ^ctx.seq1.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
      assert Decimal.equal?(hd(all).value, Decimal.new(18))
    end

    test "rejects a value above 20", ctx do
      assert {:error, :invalid_value} =
               Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 21, ctx.head.id)
    end

    test "rejects a value below 0", ctx do
      assert {:error, :invalid_value} =
               Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, -1, ctx.head.id)
    end
  end

  describe "clear_conduct_mark/2" do
    test "deletes the mark for (enrollment, sequence)", ctx do
      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 14, ctx.head.id)

      assert {:ok, 1} = Discipline.clear_conduct_mark(ctx.enrollment1, ctx.seq1)

      assert Discipline.note_de_conduite(ctx.enrollment1, {:sequence, ctx.seq1}) == nil
    end

    test "returns {:ok, 0} when no mark exists", ctx do
      assert {:ok, 0} = Discipline.clear_conduct_mark(ctx.enrollment1, ctx.seq1)
    end
  end

  describe "note_de_conduite/2" do
    test "sequence period returns that séquence's mark value", ctx do
      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 16, ctx.head.id)

      assert Decimal.equal?(
               Discipline.note_de_conduite(ctx.enrollment1, {:sequence, ctx.seq1}),
               Decimal.new(16)
             )
    end

    test "trimester period returns the MEAN (not sum) of that term's present séquence marks",
         ctx do
      term1 = Enum.find(Academics.list_terms(ctx.year), &(&1.id == ctx.seq1.term_id))
      assert ctx.seq2.term_id == term1.id

      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 10, ctx.head.id)
      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq2, 20, ctx.head.id)

      result = Discipline.note_de_conduite(ctx.enrollment1, {:trimester, term1})

      assert Decimal.equal?(result, Decimal.new(15))
      refute Decimal.equal?(result, Decimal.new(30))
    end

    test "annual period returns the mean of present séquence marks across the year", ctx do
      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 10, ctx.head.id)
      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq2, 20, ctx.head.id)

      result = Discipline.note_de_conduite(ctx.enrollment1, {:annual, ctx.year})

      assert Decimal.equal?(result, Decimal.new(15))
    end

    test "returns nil when no marks are present", ctx do
      assert Discipline.note_de_conduite(ctx.enrollment1, {:sequence, ctx.seq1}) == nil
      assert Discipline.note_de_conduite(ctx.enrollment1, {:annual, ctx.year}) == nil
    end
  end

  describe "discipline_summary/2" do
    test "splits the sanction ladder from consignes and reports note_de_conduite", ctx do
      {:ok, consigne} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :consigne, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, avertissement} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :avertissement, date: Date.add(ctx.seq1.start_date, 1)},
          ctx.head.id
        )

      {:ok, exclusion} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{
            type: :exclusion_temporaire,
            date: Date.add(ctx.seq1.start_date, 2),
            duration_days: 2
          },
          ctx.head.id
        )

      {:ok, _out_of_range} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :consigne, date: ctx.seq2.start_date},
          ctx.head.id
        )

      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 17, ctx.head.id)

      summary = Discipline.discipline_summary(ctx.enrollment1, {:sequence, ctx.seq1})

      assert Enum.map(summary.sanctions, & &1.id) == [exclusion.id, avertissement.id]
      refute Enum.any?(summary.sanctions, &(&1.id == consigne.id))
      assert summary.consignes_count == 1
      assert Decimal.equal?(summary.note_de_conduite, Decimal.new(17))
    end

    test "consignes_count and note_de_conduite are zero/nil with no entries", ctx do
      summary = Discipline.discipline_summary(ctx.enrollment2, {:sequence, ctx.seq1})

      assert summary.sanctions == []
      assert summary.consignes_count == 0
      assert summary.note_de_conduite == nil
    end
  end

  describe "class_discipline/2" do
    test "includes every roster enrollment, entry-less ones get zeros", ctx do
      {:ok, _} =
        Discipline.add_sanction(
          ctx.enrollment1,
          %{type: :blame, date: ctx.seq1.start_date},
          ctx.head.id
        )

      {:ok, _} = Discipline.set_conduct_mark(ctx.enrollment1, ctx.seq1, 13, ctx.head.id)

      result = Discipline.class_discipline(ctx.cg, {:sequence, ctx.seq1})

      assert map_size(result) == 2

      s1 = result[ctx.enrollment1.id]
      assert length(s1.sanctions) == 1
      assert Decimal.equal?(s1.note_de_conduite, Decimal.new(13))

      s2 = result[ctx.enrollment2.id]
      assert s2 == %{sanctions: [], consignes_count: 0, note_de_conduite: nil}
    end
  end
end
