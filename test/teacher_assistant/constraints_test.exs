defmodule TeacherAssistant.ConstraintsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Discipline, Fees, Organization}

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ConductMark,
    FeeAdjustment,
    Mark,
    Payment,
    Sequence
  }

  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    tc = TeacherFixtures.assigned_context_fixture(scope, year, %{teacher: head})
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(scope, tc.class_group_id)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = TeacherAssistant.Enrollment.list_roster(scope, cg)
    seq = Organization.list_sequences(scope, year) |> List.first()

    %{
      ws: ws,
      head: head,
      year: year,
      tc: tc,
      cg: cg,
      enrollment: enrollment,
      seq: seq,
      scope: scope
    }
  end

  describe "academic_years: one active year per workspace" do
    test "only one active academic year per workspace at the database level", %{scope: scope} do
      assert {:error, %Ash.Error.Invalid{}} =
               AcademicYear
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Doublon",
                   start_date: ~D[2030-09-01],
                   end_date: ~D[2031-06-30],
                   active: true
                 },
                 scope: scope
               )
               |> Ash.create()
    end

    test "a create with active: true that fails (duplicate name) leaves the previous year active",
         %{ws: _ws, year: year, scope: scope} do
      assert year.active

      assert {:error, %Ash.Error.Invalid{}} =
               Organization.create_academic_year(scope, %{
                 name: year.name,
                 start_date: ~D[2031-09-01],
                 end_date: ~D[2032-06-30],
                 active: true
               })

      {:ok, reloaded} = Organization.get_academic_year(scope, year.id)
      assert reloaded.active
    end

    test "activate still works because it deactivates siblings first", %{ws: _ws, scope: scope} do
      {:ok, y2} =
        Organization.create_academic_year(scope, %{
          name: "Suivante",
          start_date: ~D[2030-09-01],
          end_date: ~D[2031-06-30],
          active: false
        })

      assert {:ok, %{active: true}} = Organization.activate_academic_year(scope, y2)
      assert Organization.current_academic_year(scope).id == y2.id
    end

    test "create_academic_year(active: true) also deactivates the sibling first", %{
      ws: _ws,
      year: year,
      scope: scope
    } do
      assert year.active

      assert {:ok, y2} =
               Organization.create_academic_year(scope, %{
                 name: "2031-2032",
                 start_date: ~D[2031-09-01],
                 end_date: ~D[2032-06-30],
                 active: true
               })

      assert y2.active
      {:ok, reloaded} = Organization.get_academic_year(scope, year.id)
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
    test "a mark above the assessment's max score is rejected", %{
      tc: tc,
      seq: seq,
      cg: cg,
      scope: scope
    } do
      {:ok, a} =
        Assessment.create_assessment(scope, tc, seq, %{label: "D1", max_score: Decimal.new(20)})

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, cg)

      assert {:error, _} =
               Assessment.upsert_marks(scope, a, [%{student_id: s.id, score: Decimal.new("21")}])

      assert {:error, _} =
               Assessment.upsert_marks(scope, a, [%{student_id: s.id, score: Decimal.new("-1")}])
    end

    test "the ScoreWithinMax validation rejects a score above max_score directly on the resource",
         %{tc: tc, seq: seq, cg: cg, scope: scope} do
      {:ok, a} =
        Assessment.create_assessment(scope, tc, seq, %{label: "D2", max_score: Decimal.new(20)})

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, cg)

      assert {:error, %Ash.Error.Invalid{}} =
               Mark
               |> Ash.Changeset.for_create(
                 :create,
                 %{assessment_id: a.id, student_id: s.id, score: Decimal.new("21")},
                 scope: scope
               )
               |> Ash.create()
    end

    test "the score_non_negative check constraint rejects a negative score directly on the resource",
         %{tc: tc, seq: seq, cg: cg, scope: scope} do
      {:ok, a} =
        Assessment.create_assessment(scope, tc, seq, %{label: "D3", max_score: Decimal.new(20)})

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, cg)

      assert {:error, %Ash.Error.Invalid{}} =
               Mark
               |> Ash.Changeset.for_create(
                 :create,
                 %{assessment_id: a.id, student_id: s.id, score: Decimal.new("-1")},
                 scope: scope
               )
               |> Ash.create()
    end

    test "the ScoreWithinMax validation also runs on update", %{
      tc: tc,
      seq: seq,
      cg: cg,
      scope: scope
    } do
      {:ok, a} =
        Assessment.create_assessment(scope, tc, seq, %{label: "D4", max_score: Decimal.new(20)})

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, cg)

      {:ok, mark} =
        Mark
        |> Ash.Changeset.for_create(
          :create,
          %{assessment_id: a.id, student_id: s.id, score: Decimal.new("10")},
          scope: scope
        )
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               mark
               |> Ash.Changeset.for_update(:update, %{score: Decimal.new("21")}, scope: scope)
               |> Ash.update()
    end
  end

  describe "fees: tranche/payment/adjustment amount guards" do
    setup %{scope: scope, year: year} do
      {:ok, _} = Fees.create_default_fee_types(scope, year)
      [fe, _pta] = Fees.list_fee_types(scope, year)
      %{fe: fe}
    end

    test "a tranche percent outside 1..100 is rejected", %{scope: scope, year: year} do
      for percent <- [0, 101, -5] do
        assert {:error, _} =
                 Fees.add_tranche(scope, year, %{
                   label: "T1",
                   percent: percent,
                   due_date: ~D[2030-10-01]
                 })
      end
    end

    test "a non-positive payment amount is rejected", %{enrollment: e, scope: scope} do
      assert {:error, :invalid_amount} =
               Fees.record_payment(scope, e, %{amount: 0, method: :cash})
    end

    test "the payments amount_positive check constraint rejects a zero amount directly on the resource",
         %{enrollment: e, head: head, scope: scope} do
      assert {:error, %Ash.Error.Invalid{}} =
               Payment
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   amount: 0,
                   paid_on: ~D[2030-10-01],
                   method: :cash,
                   recorded_by_user_id: head.id,
                   enrollment_id: e.id,
                   academic_year_id: e.academic_year_id,
                   seq: 1,
                   number: "R2030-000001",
                   paid_to_date: 0,
                   left_after: 0,
                   student_name: "Awa",
                   class_label: "X"
                 },
                 scope: scope
               )
               |> Ash.create()
    end

    test "the fee_adjustments amount_positive check constraint rejects a zero amount", %{
      enrollment: e,
      head: head,
      scope: scope,
      fe: fe
    } do
      assert {:error, %Ash.Error.Invalid{}} =
               FeeAdjustment
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   amount: 0,
                   reason: "erreur",
                   recorded_by_user_id: head.id,
                   enrollment_id: e.id,
                   fee_type_id: fe.id
                 },
                 scope: scope
               )
               |> Ash.create()

      # The domain guard rejects it before any write.
      assert {:error, :invalid_amount} =
               Fees.set_adjustment(scope, e, fe, %{amount: 0, reason: "erreur"})
    end
  end

  describe "conduct marks: 0..20 range" do
    test "a conduct mark outside 0..20 is rejected", %{enrollment: e, seq: seq, scope: scope} do
      assert {:error, _} = Discipline.set_conduct_mark(scope, e, seq, 21)
    end

    test "the conduct_marks value_in_range check constraint rejects an out-of-range value directly on the resource",
         %{enrollment: e, seq: seq, head: head} do
      assert {:error, _} =
               ConductMark
               |> Ash.Changeset.for_create(:create, %{
                 value: Decimal.new(21),
                 recorded_by_user_id: head.id,
                 enrollment_id: e.id,
                 sequence_id: seq.id
               })
               |> Ash.Changeset.set_tenant(e.workspace_id)
               |> Ash.create()
    end
  end

  describe "sequences: ordered dates" do
    test "a sequence with end_date before start_date is rejected at the database level", %{
      ws: ws,
      year: year,
      scope: scope
    } do
      term = Organization.list_terms(scope, year) |> List.first()

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
