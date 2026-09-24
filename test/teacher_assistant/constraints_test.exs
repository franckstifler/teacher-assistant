defmodule TeacherAssistant.ConstraintsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Discipline, Fees, Organization}

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ConductMark,
    FeeAdjustment,
    FeeTranche,
    Mark,
    Payment,
    Sequence
  }

  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    tc = TeacherFixtures.assigned_context_fixture(ws, year, %{teacher: head})
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(tc.class_group_id, ws)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = TeacherAssistant.Enrollment.list_roster(cg)
    seq = year |> Organization.list_sequences() |> List.first()
    %{ws: ws, head: head, year: year, tc: tc, cg: cg, enrollment: enrollment, seq: seq}
  end

  describe "academic_years: one active year per workspace" do
    test "only one active academic year per workspace at the database level", %{ws: ws} do
      assert {:error, %Ash.Error.Invalid{}} =
               AcademicYear
               |> Ash.Changeset.for_create(:create, %{
                 name: "Doublon",
                 start_date: ~D[2030-09-01],
                 end_date: ~D[2031-06-30],
                 active: true
               })
               |> Ash.Changeset.set_tenant(ws.id)
               |> Ash.create()
    end

    test "a create with active: true that fails (duplicate name) leaves the previous year active",
         %{ws: ws, year: year} do
      assert year.active

      assert {:error, %Ash.Error.Invalid{}} =
               Organization.create_academic_year(ws, %{
                 name: year.name,
                 start_date: ~D[2031-09-01],
                 end_date: ~D[2032-06-30],
                 active: true
               })

      {:ok, reloaded} = Organization.get_academic_year(year.id, ws)
      assert reloaded.active
    end

    test "activate still works because it deactivates siblings first", %{ws: ws} do
      {:ok, y2} =
        Organization.create_academic_year(ws, %{
          name: "Suivante",
          start_date: ~D[2030-09-01],
          end_date: ~D[2031-06-30],
          active: false
        })

      assert {:ok, %{active: true}} = Organization.activate_academic_year(y2)
      assert Organization.current_academic_year(ws).id == y2.id
    end

    test "create_academic_year(active: true) also deactivates the sibling first", %{
      ws: ws,
      year: year
    } do
      assert year.active

      assert {:ok, y2} =
               Organization.create_academic_year(ws, %{
                 name: "2031-2032",
                 start_date: ~D[2031-09-01],
                 end_date: ~D[2032-06-30],
                 active: true
               })

      assert y2.active
      {:ok, reloaded} = Organization.get_academic_year(year.id, ws)
      refute reloaded.active
    end

    test "an academic year with end_date <= start_date is rejected at the database level", %{
      ws: ws
    } do
      # The resource-level `validate compare(:end_date, greater_than:
      # :start_date)` already catches this in every normal write path
      # (domain function, raw Ash.Changeset.for_create/for_update). Bypass it
      # with Ash.Seed (straight to the data layer, no changeset validations)
      # to prove the DB check constraint independently exists.
      result =
        try do
          Ash.Seed.seed!(AcademicYear, %{
            name: "Invalide",
            start_date: ~D[2030-09-01],
            end_date: ~D[2030-09-01],
            active: false,
            workspace_id: ws.id
          })

          :ok
        rescue
          _ -> :error
        end

      assert result == :error
    end
  end

  describe "marks: score bounds" do
    test "a mark above the assessment's max score is rejected", %{tc: tc, seq: seq, cg: cg} do
      {:ok, a} = Assessment.create_assessment(tc, seq, %{label: "D1", max_score: Decimal.new(20)})
      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(cg)

      assert {:error, _} =
               Assessment.upsert_marks(a, [%{student_id: s.id, score: Decimal.new("21")}])

      assert {:error, _} =
               Assessment.upsert_marks(a, [%{student_id: s.id, score: Decimal.new("-1")}])
    end

    test "the ScoreWithinMax validation rejects a score above max_score directly on the resource",
         %{tc: tc, seq: seq, cg: cg} do
      {:ok, a} = Assessment.create_assessment(tc, seq, %{label: "D2", max_score: Decimal.new(20)})
      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(cg)

      assert {:error, _} =
               Mark
               |> Ash.Changeset.for_create(:create, %{
                 assessment_id: a.id,
                 student_id: s.id,
                 score: Decimal.new("21")
               })
               |> Ash.Changeset.set_tenant(a.workspace_id)
               |> Ash.create()
    end

    test "the score_non_negative check constraint rejects a negative score directly on the resource",
         %{tc: tc, seq: seq, cg: cg} do
      {:ok, a} = Assessment.create_assessment(tc, seq, %{label: "D3", max_score: Decimal.new(20)})
      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(cg)

      assert {:error, _} =
               Mark
               |> Ash.Changeset.for_create(:create, %{
                 assessment_id: a.id,
                 student_id: s.id,
                 score: Decimal.new("-1")
               })
               |> Ash.Changeset.set_tenant(a.workspace_id)
               |> Ash.create()
    end

    test "the ScoreWithinMax validation also runs on update", %{tc: tc, seq: seq, cg: cg} do
      {:ok, a} = Assessment.create_assessment(tc, seq, %{label: "D4", max_score: Decimal.new(20)})
      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(cg)

      {:ok, mark} =
        Mark
        |> Ash.Changeset.for_create(:create, %{
          assessment_id: a.id,
          student_id: s.id,
          score: Decimal.new("10")
        })
        |> Ash.Changeset.set_tenant(a.workspace_id)
        |> Ash.create()

      assert {:error, _} =
               mark
               |> Ash.Changeset.for_update(:update, %{score: Decimal.new("21")})
               |> Ash.update()
    end
  end

  describe "fees: tranche/payment/adjustment amount guards" do
    test "a negative fee tranche amount is rejected", %{cg: cg} do
      # `Fees.add_tranche/2`'s own `validate_amount/1` guard allows a
      # zero-amount tranche (see `FeeTrancheTest."amount accepts 0"`) — the
      # DB-level `fee_tranches_amount_non_negative_check` mirrors that same
      # rule (>= 0), not a stricter one, so only a negative amount is
      # rejected here.
      assert {:error, _} =
               Fees.add_tranche(cg, %{label: "T1", amount: -1, due_date: ~D[2030-10-01]})
    end

    test "the fee_tranches amount_non_negative check constraint rejects a negative amount directly on the resource",
         %{cg: cg} do
      assert {:error, _} =
               FeeTranche
               |> Ash.Changeset.for_create(:create, %{
                 label: "T1",
                 amount: -1,
                 due_date: ~D[2030-10-01],
                 position: 0,
                 workspace_id: cg.workspace_id,
                 class_group_id: cg.id
               })
               |> Ash.create()
    end

    test "a non-positive payment amount is rejected", %{enrollment: e, head: head} do
      assert {:error, _} = Fees.record_payment(e, %{amount: 0, method: :cash}, head.id)
    end

    test "the payments amount_positive check constraint rejects a zero amount directly on the resource",
         %{enrollment: e, head: head} do
      assert {:error, _} =
               Payment
               |> Ash.Changeset.for_create(:create, %{
                 amount: 0,
                 paid_on: ~D[2030-10-01],
                 method: :cash,
                 recorded_by_user_id: head.id,
                 workspace_id: e.workspace_id,
                 enrollment_id: e.id
               })
               |> Ash.create()
    end

    test "the fee_adjustments amount_non_zero check constraint rejects a zero amount", %{
      enrollment: e,
      head: head
    } do
      assert {:error, _} =
               FeeAdjustment
               |> Ash.Changeset.for_create(:create, %{
                 amount: 0,
                 reason: "erreur",
                 recorded_by_user_id: head.id,
                 workspace_id: e.workspace_id,
                 enrollment_id: e.id
               })
               |> Ash.create()

      # Also reachable through the domain function, whose own guard only
      # rejects a negative amount, not zero.
      assert {:error, _} = Fees.set_adjustment(e, %{amount: 0, reason: "erreur"}, head.id)
    end
  end

  describe "conduct marks: 0..20 range" do
    test "a conduct mark outside 0..20 is rejected", %{enrollment: e, seq: seq, head: head} do
      assert {:error, _} = Discipline.set_conduct_mark(e, seq, 21, head.id)
    end

    test "the conduct_marks value_in_range check constraint rejects an out-of-range value directly on the resource",
         %{enrollment: e, seq: seq, head: head} do
      assert {:error, _} =
               ConductMark
               |> Ash.Changeset.for_create(:create, %{
                 value: Decimal.new(21),
                 recorded_by_user_id: head.id,
                 workspace_id: e.workspace_id,
                 enrollment_id: e.id,
                 sequence_id: seq.id
               })
               |> Ash.create()
    end
  end

  describe "sequences: ordered dates" do
    test "a sequence with end_date before start_date is rejected at the database level", %{
      ws: ws,
      year: year
    } do
      term = year |> Organization.list_terms() |> List.first()

      assert {:error, _} =
               Sequence
               |> Ash.Changeset.for_create(:create, %{
                 number: 99,
                 position_in_term: 1,
                 start_date: ~D[2030-09-10],
                 end_date: ~D[2030-09-01],
                 term_id: term.id
               })
               |> Ash.Changeset.set_tenant(ws.id)
               |> Ash.create()
    end
  end
end
