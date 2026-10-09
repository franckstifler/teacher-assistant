defmodule TeacherAssistant.ReportCardsAccessTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "5e B", level: "5ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})

    %{teacher: teacher, scope: tscope, teaching_context: tc} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg})

    tscope = %{tscope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)

    %{
      scope: scope,
      tscope: tscope,
      teacher: teacher,
      tc: tc,
      cg: cg,
      other: other,
      term: term,
      year: year
    }
  end

  test "access: admin full, teacher of the class published, others none", ctx do
    assert ReportCards.access(ctx.scope, ctx.cg) == :full
    assert ReportCards.access(ctx.tscope, ctx.cg) == :published
    assert ReportCards.access(ctx.tscope, ctx.other) == :none
    assert ReportCards.can_publish?(ctx.scope)
    refute ReportCards.can_publish?(ctx.tscope)
  end

  test "a teacher sees only published periods, never live figures", ctx do
    period = {:trimester, ctx.term}
    assert ReportCards.view_for(ctx.tscope, ctx.cg, period) == :not_published
    [seq | _] = ctx.term.sequences
    assert ReportCards.view_for(ctx.tscope, ctx.cg, {:sequence, seq}) == :not_published
    assert ReportCards.view_for(ctx.tscope, ctx.other, period) == :forbidden

    assert {:draft, _} = ReportCards.view_for(ctx.scope, ctx.cg, period)
    {:ok, pub} = TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, ctx.term)
    assert {:published, %{id: id}, _view} = ReportCards.view_for(ctx.tscope, ctx.cg, period)
    assert id == pub.id
  end

  test "visible classes", ctx do
    assert ctx.scope
           |> ReportCards.visible_classes(ctx.year)
           |> Enum.map(& &1.id)
           |> Enum.member?(ctx.other.id)

    assert ctx.tscope |> ReportCards.visible_classes(ctx.year) |> Enum.map(& &1.id) == [ctx.cg.id]
  end

  test "periods are the séquences, then the terms, then the year", ctx do
    terms = Organization.list_terms(ctx.scope, ctx.year)
    params = ctx.scope |> ReportCards.periods(ctx.year) |> Enum.map(&elem(&1, 0))
    n_seq = ctx.scope |> Organization.list_sequences(ctx.year) |> length()
    assert List.last(params) == "annee"
    assert length(params) == n_seq + length(terms) + 1
    assert hd(params) =~ "seq:"
    assert ("trim:" <> ctx.term.id) in params
  end

  test "entry rate over the term's séquences", ctx do
    period = {:trimester, ctx.term}
    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 0

    [seq | _] = ctx.term.sequences

    {:ok, a} =
      Assessment.create_assessment(ctx.scope, ctx.tc, seq, %{
        label: "D",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: st}] = Enrollment.list_roster(ctx.scope, ctx.cg)
    :ok = Assessment.upsert_marks(ctx.scope, a, [%{student_id: st.id, score: Decimal.new(12)}])
    # first séquence complete, second séquence has no assessment yet (0 %)
    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 50

    for seq <- tl(ctx.term.sequences) do
      {:ok, b} =
        Assessment.create_assessment(ctx.scope, ctx.tc, seq, %{
          label: "D",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      :ok = Assessment.upsert_marks(ctx.scope, b, [%{student_id: st.id, score: Decimal.new(12)}])
    end

    assert ReportCards.entry_rate(ctx.scope, ctx.cg, period) == 100
  end
end
